import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SecureTokenStore] 의 저장/조회/삭제 왕복과 SharedPreferences 1회 마이그레이션.
///
/// 네트워크도, 실기기도 타지 않는다.
/// - 보안 저장소: `FlutterSecureStorage.setMockInitialValues` (인메모리 맵)
/// - SharedPreferences: `SharedPreferences.setMockInitialValues` (인메모리 맵)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SecureTokenStore 토큰 왕복', () {
    test('accessToken 은 저장하면 읽히고 지우면 null 이 된다', () async {
      final store = SecureTokenStore();

      expect(await store.readAccessToken(), isNull);

      await store.writeAccessToken('eyJ.access.token');
      expect(await store.readAccessToken(), 'eyJ.access.token');

      await store.deleteAccessToken();
      expect(await store.readAccessToken(), isNull);
    });

    test('refreshToken 은 저장하면 읽히고 지우면 null 이 된다', () async {
      final store = SecureTokenStore();

      expect(await store.readRefreshToken(), isNull);

      await store.writeRefreshToken('eyJ.refresh.token');
      expect(await store.readRefreshToken(), 'eyJ.refresh.token');

      await store.deleteRefreshToken();
      expect(await store.readRefreshToken(), isNull);
    });

    test('accessToken 과 refreshToken 은 서로 다른 키라 간섭하지 않는다', () async {
      final store = SecureTokenStore();

      await store.writeAccessToken('access');
      await store.writeRefreshToken('refresh');

      expect(await store.readAccessToken(), 'access');
      expect(await store.readRefreshToken(), 'refresh');

      await store.deleteAccessToken();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), 'refresh');
    });

    test('clear 는 액세스와 리프레시 토큰을 모두 지운다', () async {
      final store = SecureTokenStore();
      await store.writeAccessToken('access');
      await store.writeRefreshToken('refresh');

      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('새 인스턴스로 다시 읽어도 저장된 토큰이 남아 있다', () async {
      // 앱 재시작 근사 — 저장소 인스턴스를 새로 만들어 다시 읽는다.
      await SecureTokenStore().writeAccessToken('eyJ.persisted.token');

      expect(await SecureTokenStore().readAccessToken(), 'eyJ.persisted.token');
    });

    test('저장된 값은 평문 키 jwt_token 이 아니라 access_token 키에 들어간다', () async {
      await SecureTokenStore().writeAccessToken('eyJ.access.token');

      const raw = FlutterSecureStorage();
      expect(await raw.read(key: SecureTokenStore.accessTokenKey),
          'eyJ.access.token');
      expect(await raw.read(key: SecureTokenStore.legacySharedPrefsKey),
          isNull);
    });
  });

  group('SecureTokenStore 1회 마이그레이션', () {
    test('SharedPreferences 의 기존 jwt_token 이 보안 저장소로 옮겨지고 원본은 삭제된다',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'jwt_token': 'eyJ.old.token',
      });
      final store = SecureTokenStore();

      final moved = await store.migrateLegacyToken();

      expect(moved, isTrue);
      expect(await store.readAccessToken(), 'eyJ.old.token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
    });

    test('마이그레이션을 두 번 실행해도 옮겨둔 토큰이 사라지지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'jwt_token': 'eyJ.old.token',
      });
      final store = SecureTokenStore();

      await store.migrateLegacyToken();
      final secondRun = await store.migrateLegacyToken();

      expect(secondRun, isFalse, reason: '두 번째 실행에는 옮길 게 없다');
      expect(await store.readAccessToken(), 'eyJ.old.token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
    });

    test('옮길 토큰이 없으면 보안 저장소를 건드리지 않는다', () async {
      final store = SecureTokenStore();

      final moved = await store.migrateLegacyToken();

      expect(moved, isFalse);
      expect(await store.readAccessToken(), isNull);
    });

    test('보안 저장소에 이미 토큰이 있으면 구버전 값으로 덮어쓰지 않는다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'jwt_token': 'eyJ.old.token',
      });
      final store = SecureTokenStore();
      await store.writeAccessToken('eyJ.new.token');

      await store.migrateLegacyToken();

      expect(await store.readAccessToken(), 'eyJ.new.token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull, reason: '평문 잔재는 어쨌든 지운다');
    });

    test('빈 문자열이 남아 있으면 옮기지 않고 평문 키만 지운다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'jwt_token': ''});
      final store = SecureTokenStore();

      final moved = await store.migrateLegacyToken();

      expect(moved, isFalse);
      expect(await store.readAccessToken(), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
    });
  });
}

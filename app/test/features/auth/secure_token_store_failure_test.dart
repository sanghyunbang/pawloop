import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';

/// 일부 Android 기기에서 Keystore 가 깨져 `PlatformException` 이 올라오는 사례가
/// 알려져 있다. 그대로 던지면 앱이 시작조차 못 하므로 읽기 실패는 "토큰 없음"이어야 한다.
///
/// `TestFlutterSecureStoragePlatform` 과 같은 방식으로 가짜 플랫폼을 손으로 만들어
/// `FlutterSecureStoragePlatform.instance` 에 꽂는다.
class _ThrowingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  int readCalls = 0;
  int deleteCalls = 0;

  static PlatformException _keystoreFailure(String op) => PlatformException(
        code: 'Exception encountered',
        message: op,
        details: 'javax.crypto.BadPaddingException: pad block corrupted',
      );

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    readCalls++;
    throw _keystoreFailure('read');
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    deleteCalls++;
    throw _keystoreFailure('delete');
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      throw _keystoreFailure('containsKey');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw _keystoreFailure('deleteAll');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      throw _keystoreFailure('readAll');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      throw _keystoreFailure('write');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('보안 저장소가 터졌을 때', () {
    late _ThrowingSecureStoragePlatform platform;

    setUp(() {
      platform = _ThrowingSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = platform;
    });

    tearDown(() {
      // 다른 테스트에 영향이 가지 않게 인메모리 가짜로 되돌린다.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    test('accessToken 읽기가 Keystore 예외를 삼키고 null 을 돌려준다', () async {
      final store = SecureTokenStore();

      expect(await store.readAccessToken(), isNull);
      expect(platform.readCalls, 1, reason: '실제로 저장소를 읽으려 시도했어야 한다');
    });

    test('refreshToken 읽기도 Keystore 예외를 삼키고 null 을 돌려준다', () async {
      final store = SecureTokenStore();

      expect(await store.readRefreshToken(), isNull);
      expect(platform.readCalls, 1);
    });

    test('로그아웃(clear)은 삭제가 실패해도 예외를 던지지 않는다', () async {
      final store = SecureTokenStore();

      await expectLater(store.clear(), completes);
      expect(platform.deleteCalls, 2, reason: '액세스/리프레시 둘 다 지우려 시도한다');
    });
  });

  group('플랫폼 보안 옵션', () {
    test('Android 는 EncryptedSharedPreferences 를 켠다', () {
      final options = SecureTokenStore().storage.aOptions.toMap();

      expect(options['encryptedSharedPreferences'], 'true');
    });

    test('iOS Keychain 접근성은 first_unlock_this_device 다', () {
      final options = SecureTokenStore().storage.iOptions.toMap();

      expect(options['accessibility'], 'first_unlock_this_device');
    });
  });
}

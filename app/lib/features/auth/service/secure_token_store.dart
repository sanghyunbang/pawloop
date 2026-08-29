import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 인증 토큰을 OS 보안 저장소에 보관하는 단일 창구.
///
/// - Android: `EncryptedSharedPreferences`(Keystore 기반) 사용.
/// - iOS: Keychain. 접근성은 `first_unlock_this_device`
///   (기기 재시작 후 첫 잠금해제 이후 접근 가능 + 백업/다른 기기로 넘어가지 않음).
///
/// 이전에는 `TokenStorage`(static) 와 `TokenProvider`(인터페이스)가 같은
/// `jwt_token` 키를 각자 SharedPreferences 평문으로 다뤘다. 저장 책임은
/// 이 클래스 하나로 모았고, `TokenStorage` 는 호출부 호환을 위한 얇은
/// 위임 래퍼로만 남아 있다.
///
/// 읽기는 절대 예외를 던지지 않는다. 일부 Android 기기에서 Keystore 가
/// 깨져 `PlatformException` 이 나는 사례가 알려져 있는데, 그대로 던지면
/// 앱이 시작조차 못 한다. 읽기 실패는 "토큰 없음"(null)으로 처리해
/// 로그인 화면으로 보낸다.
class SecureTokenStore {
  /// 액세스 토큰 키.
  static const String accessTokenKey = 'access_token';

  /// 리프레시 토큰 키. 실제 값은 #9(Refresh Token)에서 채워진다.
  static const String refreshTokenKey = 'refresh_token';

  /// SharedPreferences 에 평문으로 저장돼 있던 구버전 키.
  /// 1회 마이그레이션 이후로는 어디에서도 쓰지 않는다.
  static const String legacySharedPrefsKey = 'jwt_token';

  /// Android: Keystore 로 암호화되는 EncryptedSharedPreferences 를 쓴다.
  static const AndroidOptions androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  /// iOS: 백업으로 새어 나가지 않도록 `first_unlock_this_device`.
  static const IOSOptions iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: androidOptions,
    iOptions: iosOptions,
  );

  /// 앱 전역에서 쓰는 인스턴스.
  static final SecureTokenStore instance = SecureTokenStore();

  final FlutterSecureStorage _storage;

  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  /// 실제로 쓰는 저장소. 옵션(Keystore/Keychain 설정) 검증용.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  // ── 원시 read/write/delete ─────────────────────────────────────────────

  /// [key] 의 값을 읽는다. 저장소가 터지면 예외를 삼키고 null 을 돌려준다.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      // Keystore/Keychain 손상 등. 앱을 죽이지 않고 "토큰 없음"으로 본다.
      if (kDebugMode) {
        debugPrint('[SecureTokenStore] read 실패(key=$key): ${e.runtimeType}');
      }
      return null;
    }
  }

  /// [key] 에 [value] 를 저장한다.
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  /// [key] 를 삭제한다. 로그아웃이 예외로 막히면 안 되므로 실패를 삼킨다.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureTokenStore] delete 실패(key=$key): ${e.runtimeType}');
      }
    }
  }

  // ── 액세스 토큰 ────────────────────────────────────────────────────────

  Future<String?> readAccessToken() => read(accessTokenKey);

  Future<void> writeAccessToken(String token) =>
      write(accessTokenKey, token);

  Future<void> deleteAccessToken() => delete(accessTokenKey);

  // ── 리프레시 토큰 (#9) ─────────────────────────────────────────────────

  Future<String?> readRefreshToken() => read(refreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      write(refreshTokenKey, token);

  Future<void> deleteRefreshToken() => delete(refreshTokenKey);

  /// 로그인/갱신 결과를 한 번에 저장한다.
  ///
  /// [refreshToken] 이 null 이면 **기존 값을 지우지 않는다.** refresh 를 주지 않는
  /// 경로(옛 서버, `refresh` 파라미터 없는 딥링크)에서 멀쩡히 살아 있는 RT 를
  /// 날려 사용자를 재로그인시키지 않기 위해서다. RT 를 없애는 것은 로그아웃
  /// ([clear])의 일이다.
  Future<void> writeTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await writeAccessToken(accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await writeRefreshToken(refreshToken);
    }
  }

  /// 로그아웃: 액세스/리프레시 둘 다 지운다.
  Future<void> clear() async {
    await deleteAccessToken();
    await deleteRefreshToken();
  }

  // ── 1회 마이그레이션 ───────────────────────────────────────────────────

  /// 구버전에서 SharedPreferences 에 평문으로 남아 있던 `jwt_token` 을
  /// 보안 저장소로 옮기고 SharedPreferences 에서 지운다.
  ///
  /// 앱 시작 시 로그인 상태를 복원하기 **전에** 한 번 호출한다.
  /// 기존 사용자는 재로그인 없이 그대로 넘어온다.
  ///
  /// 멱등적이다 — 옮길 게 없으면 보안 저장소를 건드리지 않는다.
  /// 보안 저장소에 이미 값이 있으면 덮어쓰지 않는다.
  ///
  /// 옮긴 게 있으면 true.
  Future<bool> migrateLegacyToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacySharedPrefsKey);
      if (legacy == null) return false;

      if (legacy.isNotEmpty) {
        final existing = await readAccessToken();
        if (existing == null || existing.isEmpty) {
          // 실패하면 아래 remove 까지 못 가므로 평문 토큰은 남는다.
          // 다음 실행에서 다시 시도한다 (로그인 상태를 잃는 것보다 낫다).
          await writeAccessToken(legacy);
        }
      }

      await prefs.remove(legacySharedPrefsKey);
      return legacy.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SecureTokenStore] 마이그레이션 실패: ${e.runtimeType}');
      }
      return false;
    }
  }
}

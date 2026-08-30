// lib/v2/data/auth_state.dart
//
// 앱이 "지금 누가 로그인해 있는가" 를 아는 **단 하나의 자리** — 이슈 #12.
//
// ## 무엇이 문제였나
//
// 예전에는 `ValueNotifier<bool> loggedIn` 하나가 전부였고, 그 값은
// **저장된 토큰 문자열이 비어 있지 않은가** 로만 정해졌다. 거기서 파생된 것들:
//
//  1. 내가 누군지 모른다 — `GET /auth/me` 를 한 번도 부르지 않아 닉네임을 못 띄운다.
//  2. 서버가 폐기한 토큰을 들고도 `loggedIn = true` 다. 첫 API 호출에서 조용히 401.
//  3. 신규 가입인지 모른다 — 온보딩을 붙일 자리가 없다.
//  4. 로그아웃이 로컬 토큰만 지운다 — 서버의 refresh 토큰은 계속 살아 있다(#9).
//
// ## 상태 머신
//
//     unknown ──(토큰 있음 + /auth/me 200)──> authenticated
//        │                                        ▲
//        └──(토큰 없음 · 401 · 갱신 실패)──> unauthenticated
//                                                 │
//     unauthenticated ──(소셜 버튼 탭)──> authenticating
//     authenticating ──(성공 & isNew)──> onboarding ──(온보딩 완료)──> authenticated
//     authenticating ──(성공 & !isNew)──> authenticated
//     authenticating ──(취소·실패)──> unauthenticated
//     authenticated ──(로그아웃 · 세션 만료)──> unauthenticated
//
// [AuthStatus.unknown] 은 **스플래시 구간**이다. 이 상태가 없으면 앱이 로그인 화면을
// 한 프레임 보여줬다가 홈으로 튀는 깜빡임이 생긴다([init] 이 네트워크를 타기 때문이다).
//
// ## 왜 정적 클래스인가
//
// 화면 세 곳(`main.dart`·`me_screen.dart`·`login_screen.dart`)과 라우터가 같은 값을
// 본다. Provider 로 감싸면 라우터의 `redirect` 가 `BuildContext` 없이 상태를 읽을 수
// 없다. 대신 의존성(토큰 저장소·HTTP)은 [configureForTest] 로 갈아끼울 수 있게 두어
// 유닛 테스트가 플랫폼 채널 없이 돈다(정책 #21).

import 'package:flutter/foundation.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';

/// 인증 상태 머신의 상태값.
enum AuthStatus {
  /// 앱 시작 직후. 저장된 토큰을 서버에 물어보는 중이다 — 스플래시를 띄운다.
  unknown,

  /// 로그인하지 않았다. **앱을 쓸 수 없다는 뜻이 아니다** — 공개 라우트는 그대로 돈다.
  unauthenticated,

  /// 소셜 로그인 왕복 중(외부 브라우저가 떠 있다).
  authenticating,

  /// 인증은 됐지만 신규 가입이라 온보딩이 남았다(`isNew == true`).
  onboarding,

  /// 서버가 확인해 준 로그인 상태. [AuthState.user] 가 채워져 있다.
  authenticated,
}

/// 서버(`GET /auth/me`)가 알려준 나.
///
/// 계약 `User` 의 11개 필드 중 **앱이 실제로 쓰는 것만** 담는다. 전부 복사해 두면
/// 계약이 바뀔 때마다 여기도 따라 바뀌어야 하고, 쓰지 않는 필드는 낡아도 아무도 모른다.
@immutable
class AuthUser {
  /// `users.id`. 계약상 `User` 의 유일한 필수 필드다.
  final int id;

  /// 계정 출처(`local`·`kakao`·`google`…). 백필 전 옛 행은 null 일 수 있다.
  final String? provider;

  /// 표시용 이름. 소셜 가입 경로에서는 설정되지 않아 null 일 수 있다(#7).
  final String? nickname;

  /// 로그인 ID. 소셜 공급자가 주지 않으면 null 이다.
  final String? email;

  /// 프로필 이미지 URL.
  final String? imageUrl;

  const AuthUser({
    required this.id,
    this.provider,
    this.nickname,
    this.email,
    this.imageUrl,
  });

  /// `GET /auth/me` 의 200 본문을 읽는다. **`id` 가 없으면 null** — 계약이
  /// `required: [id]` 로 못 박은 이유가 이것이다. id 없는 사용자로는 아무것도 못 한다.
  ///
  /// 예외를 던지지 않는다. 계약과 다른 본문이 오면 "로그인 아님" 으로 다룬다.
  static AuthUser? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) return null;

    String? str(String key) {
      final v = json[key];
      return (v is String && v.trim().isNotEmpty) ? v : null;
    }

    return AuthUser(
      id: id,
      provider: str('provider'),
      nickname: str('nickname'),
      email: str('email'),
      imageUrl: str('imageUrl'),
    );
  }

  /// 화면에 띄울 이름. 닉네임이 없으면 이메일, 그것도 없으면 안내 문구.
  String get displayName => nickname ?? email ?? '이름 없는 계정';
}

/// 전역 인증 상태.
class AuthState {
  const AuthState._();

  /// 현재 상태. 라우터의 `refreshListenable` 이 이것을 듣는다.
  static final ValueNotifier<AuthStatus> status =
      ValueNotifier<AuthStatus>(AuthStatus.unknown);

  static AuthUser? _user;

  static bool _sessionEnded = false;

  /// **방금** 세션이 끝났는가 — 로그아웃했거나, 저장된 토큰이 서버에서 거부됐거나(#11).
  ///
  /// ## 왜 이 플래그가 따로 필요한가
  ///
  /// "로그인한 적 없는 사람" 과 "방금 로그아웃당한 사람" 은 같은
  /// [AuthStatus.unauthenticated] 지만 보여 줘야 할 화면이 다르다.
  ///
  ///  - 전자는 그냥 둘러보게 둔다. 지도를 보다가 로그인 화면으로 튕기면 앱이 고장 난 것이다.
  ///  - 후자는 **로그인 화면을 보여 줘야 한다.** 폐기된 토큰으로 앱을 켰는데 아무 일도
  ///    없었다는 듯 홈이 뜨면, 사용자는 자기가 로그아웃됐다는 사실 자체를 모른다.
  ///
  /// 라우터가 한 번 읽고 [consumeSessionEnded] 로 지운다 — 1회성 신호다.
  static bool get sessionEnded => _sessionEnded;

  /// 신호를 소비한다. 지우지 않으면 로그인 화면을 닫을 때마다 다시 끌려온다.
  static void consumeSessionEnded() => _sessionEnded = false;

  /// 서버가 확인해 준 사용자. [AuthStatus.authenticated]·[AuthStatus.onboarding]
  /// 일 때만 채워져 있다.
  static AuthUser? get user => _user;

  /// 보호된 라우트를 열어도 되는가.
  ///
  /// **온보딩 중은 포함하지 않는다** — 인증은 됐지만 아직 프로필이 없어서, 보호
  /// 라우트를 열어 주면 반쯤 빈 화면을 보게 된다. 라우터가 온보딩에 붙잡아 둔다.
  static bool get isAuthenticated => status.value == AuthStatus.authenticated;

  // ── 의존성 (테스트에서 교체) ─────────────────────────────────────────────

  static AuthTokenStore? _tokenStore;
  static AuthRepositoryImpl? _repository;

  static AuthTokenStore get _store => _tokenStore ??= SecureAuthTokenStore();
  static AuthRepositoryImpl get _repo => _repository ??= AuthRepositoryImpl();

  /// 유닛 테스트에서 토큰 저장소와 HTTP 를 갈아끼운다.
  ///
  /// 실기기 저장소(`flutter_secure_storage`)는 플랫폼 채널이라 `flutter_test`
  /// 안에서 쓰기가 던진다. 이 자리가 없으면 [init]·[logout] 을 테스트할 수 없다.
  @visibleForTesting
  static void configureForTest({
    AuthTokenStore? tokenStore,
    AuthRepositoryImpl? repository,
  }) {
    _tokenStore = tokenStore;
    _repository = repository;
  }

  /// 테스트 간 상태 누수를 막는다. 정적 상태를 쓰는 대가다.
  @visibleForTesting
  static void resetForTest() {
    _tokenStore = null;
    _repository = null;
    _user = null;
    _sessionEnded = false;
    status.value = AuthStatus.unknown;
  }

  // ── 앱 시작 ────────────────────────────────────────────────────────────

  /// 저장된 토큰으로 **서버에 물어봐서** 상태를 확정한다.
  ///
  /// 세 갈래다.
  ///  - 토큰 없음 → [AuthStatus.unauthenticated]
  ///  - `GET /auth/me` 200 → [AuthStatus.authenticated] (+ [user] 보관)
  ///  - 401 (그리고 `AuthedClient` 의 갱신도 실패) → [AuthStatus.unauthenticated]
  ///
  /// **토큰 문자열의 존재만 보고 로그인으로 치지 않는다.** 그렇게 하면 서버가 폐기한
  /// 토큰을 들고도 홈으로 들어가고, 첫 API 호출에서 조용히 실패한다(완료 조건 4·11).
  ///
  /// 네트워크 오류는 예외다 — 로그아웃시키지 **않는다.** 비행기 모드로 앱을 켰다고
  /// 재로그인을 시키면 토큰이 멀쩡한데도 사용자를 쫓아내는 셈이다. 토큰을 그대로 두고
  /// [AuthStatus.authenticated] 로 두되 [user] 는 비워 둔다 — 그 토큰이 실제로 죽었다면
  /// 다음 요청의 401 이 `AuthedClient` 를 통해 [markSessionExpired] 로 이어진다.
  static Future<void> init() async {
    status.value = AuthStatus.unknown;
    _user = null;

    final token = await _store.readAccessToken();
    if (token == null || token.isEmpty) {
      status.value = AuthStatus.unauthenticated;
      return;
    }

    final me = await _repo.fetchMe();
    switch (me.outcome) {
      case MeOutcome.ok:
        _user = AuthUser.fromJson(me.user!);
        // id 없는 본문은 계약 위반이다. 로그인으로 치지 않는다.
        status.value =
            _user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
      case MeOutcome.unauthorized:
        // 토큰은 AuthedClient 가 이미 지웠다(_endSession). 여기서는 상태만 맞춘다.
        //
        // **토큰을 들고 시작했는데 거부당했다** — 이 사람은 로그인해 있다고 믿고 있다.
        // 아무 일 없다는 듯 홈을 띄우면 자기가 로그아웃됐다는 사실 자체를 모른다.
        // 라우터가 이 신호를 보고 로그인 화면으로 보낸다(완료 조건 4).
        _sessionEnded = true;
        status.value = AuthStatus.unauthenticated;
      case MeOutcome.networkError:
        status.value = AuthStatus.authenticated;
    }
  }

  // ── 로그인 ─────────────────────────────────────────────────────────────

  /// 외부 브라우저를 여는 순간. 화면이 "진행 중" 을 그릴 수 있게 한다.
  static void beginAuthenticating() =>
      status.value = AuthStatus.authenticating;

  /// 로그인이 성공해 토큰이 저장된 **뒤에** 부른다.
  ///
  /// `GET /auth/me` 로 나를 확정하고, [isNew] 면 온보딩으로 보낸다.
  /// [isNew] 는 로그인 응답(`AuthTokens.isNew`)에서 온다 — 이메일 로그인은
  /// `POST /auth/login`, 소셜은 1회용 코드 교환(`POST /auth/oauth/{provider}/callback`)의
  /// 응답이다(#14). **프로필의 영속 속성이 아니라 1회성 이벤트**다.
  ///
  /// #14 이전에는 소셜 경로에 이 값을 실어 나를 채널이 없어(딥링크는 토큰만 실었다)
  /// 소셜 신규 가입자가 온보딩으로 가지 못했다.
  static Future<void> completeLogin({required bool isNew}) async {
    final me = await _repo.fetchMe();
    if (me.outcome == MeOutcome.unauthorized) {
      status.value = AuthStatus.unauthenticated;
      return;
    }
    if (me.outcome == MeOutcome.ok) {
      _user = AuthUser.fromJson(me.user!);
    }
    // 네트워크 오류로 프로필을 못 받아도 로그인 자체는 성립한다 — 토큰은 방금 받았다.
    status.value = isNew ? AuthStatus.onboarding : AuthStatus.authenticated;
  }

  /// 로그인 왕복이 취소되거나 실패했을 때. [AuthStatus.authenticating] 을 되돌린다.
  static void cancelAuthenticating() {
    if (status.value == AuthStatus.authenticating) {
      status.value = AuthStatus.unauthenticated;
    }
  }

  /// 온보딩(반려동물 프로필 등록)을 마쳤다.
  static void completeOnboarding() {
    if (status.value == AuthStatus.onboarding) {
      status.value = AuthStatus.authenticated;
    }
  }

  // ── 로그아웃 ───────────────────────────────────────────────────────────

  /// `POST /auth/logout` 으로 **서버측 세션(전 기기)을 폐기**하고 로컬 토큰을 지운다.
  ///
  /// > ⚠️ **로컬 삭제는 서버 응답 성공 분기 안에 있으면 안 된다.**(완료 조건 12)
  /// > 비행기 모드에서 로그아웃 버튼을 눌렀는데 토큰이 남아 있으면, 사용자는
  /// > 로그아웃했다고 믿는 채로 다음 실행에서 다시 로그인 상태가 된다.
  /// > 서버 호출은 "해 보고 안 되면 만다" 이고, 로컬 삭제는 **무조건**이다.
  ///
  /// 서버 폐기가 실패한 경우 그 기기의 refresh 토큰은 서버에 남지만 앱에서는
  /// 지워졌으므로 쓸 수 없고, 14일 뒤 만료된다(계약 `POST /auth/logout` 주석).
  static Future<void> logout() async {
    try {
      await _repo.logout();
    } catch (e) {
      // 네트워크 없음·5xx 어느 쪽이든 사용자는 나가야 한다. 삼키고 계속한다.
      if (kDebugMode) {
        debugPrint('[AuthState] 서버 로그아웃 실패(로컬은 계속 지운다): ${e.runtimeType}');
      }
    }

    await clearLocalSession();
  }

  /// 서버를 부르지 않고 **로컬 세션만** 지운다.
  ///
  /// 서버측 세션이 이미 없는 경우에만 쓴다 — 지금은 회원 탈퇴 한 곳뿐이다
  /// (계정이 지워졌으므로 `POST /auth/logout` 은 401 이다).
  ///
  /// > ⚠️ **토큰 저장소를 화면에서 직접 비우지 마라.** 그렇게 하면 토큰은
  /// > 없는데 [status] 는 `authenticated` 로 남는 상태가 만들어지고,
  /// > `authRedirect` 가 그 상태에서 로그인 화면 진입을 홈으로 되튕긴다 —
  /// > 사용자는 로그아웃 버튼을 눌렀는데 계속 로그인된 것처럼 보인다.
  /// > 이 함정을 구조적으로 막기 위해 `TokenStorage.clearToken()` 은
  /// > **삭제했다**(#12). 지우는 경로는 이 파일 하나다.
  static Future<void> clearLocalSession() async {
    await _store.clear();
    _user = null;
    _sessionEnded = true;
    status.value = AuthStatus.unauthenticated;
  }

  /// `AuthedClient` 가 갱신에 실패했을 때 부르는 훅(#11). 토큰은 그쪽이 이미 지웠다.
  static void markSessionExpired() {
    _user = null;
    _sessionEnded = true;
    status.value = AuthStatus.unauthenticated;
  }
}

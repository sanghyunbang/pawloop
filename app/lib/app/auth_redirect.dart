// lib/app/auth_redirect.dart
//
// 라우팅의 인증 가드 — **순수 함수로만** 적는다(이슈 #12, 정책 #21).
//
// `GoRouter` 의 `redirect` 콜백 안에 규칙을 적으면 그 규칙을 시험하려고 라우터를
// 세우고 화면을 pump 해야 한다. 규칙 자체는 `(상태, 경로) → 경로?` 일 뿐이므로
// 그 형태로 떼어내면 표 하나로 검증할 수 있다. `oauth_callback.dart` 가 같은 선례다.

import 'package:heat_trip_flutter/v2/data/auth_state.dart';

/// 앱 시작 직후 토큰을 검증하는 동안 머무는 곳.
const String splashRoute = '/splash';

/// 소셜 로그인 화면(정본). `auth_routes.dart` 의 name 'login'.
const String loginRoute = '/auth/login';

/// 신규 가입자가 반려동물 프로필을 등록하는 곳.
const String onboardingRoute = '/onboarding';

/// 약관 동의를 받는 곳 — 이슈 #180.
///
/// **온보딩보다 앞이다.** 반려동물을 등록하는 것도 개인정보 처리이고, 위치는 그보다
/// 먼저 쓰일 수 있다(둘러보기의 '내 주변'). 동의를 뒤에 두면 그 사이가 비어 버린다.
const String consentRoute = '/consent';

/// 로그인 후 돌아갈 기본 자리.
const String homeRoute = '/home';

/// **로그인해야 열리는** 경로의 접두사.
///
/// ## 왜 화이트리스트가 아니라 블랙리스트인가
///
/// 이 앱은 "그냥 둘러보기" 가 성립하는 구조다 — 지도·탐색·피드는 로그인 없이 돈다.
/// 전부 막고 예외를 열면, 새 공개 화면을 추가할 때마다 로그인 벽에 부딪히고
/// 그 원인은 라우터에 있어서 화면 쪽만 보면 절대 못 찾는다. 그래서 **막을 것만
/// 명시적으로 적는다.** 새 화면의 기본값은 공개다.
///
/// 여기 있는 것들은 전부 "내 데이터" 다 — 서버가 주체를 알아야 응답할 수 있다.
const List<String> protectedRoutePrefixes = [
  // v2 의 화면은 라우트가 아니라 `Navigator.push` 로 열리므로 여기서 잡을 수 없고, 로그인이
  // 필요한 동작은 그 화면이 스스로 안내한다(`startWalk()` · `writePost()`). 라우트로 존재하는
  // 보호 화면은 온보딩뿐이다 — 레거시 셸의 `/profile/edit` · `/bookmarks` · `/record/create` 는
  // #94 로 셸과 함께 지웠다(2026-09-06).
  onboardingRoute, // 온보딩은 인증된 신규 가입자만
];

/// 로그인 상태에서는 머무를 이유가 없는 경로.
const List<String> _authOnlyEntryRoutes = [loginRoute, '/auth/sign-up'];

/// [location] 이 로그인해야 열리는 곳인가.
bool isProtectedRoute(String location) {
  final path = _pathOf(location);
  return protectedRoutePrefixes.any(
    (prefix) => path == prefix || path.startsWith('$prefix/'),
  );
}

/// 인증 상태와 가려는 경로만 보고 **어디로 보낼지** 정한다.
/// 그대로 두면 null(= 리다이렉트 없음).
///
/// [pendingLocation] 은 스플래시로 튕기기 전에 가려던 곳이다. 상태가 확정되면
/// 그 자리로 돌려보낸다 — 없으면 [homeRoute].
///
/// [sessionEnded] 는 **방금** 로그아웃했거나 저장된 토큰이 거부된 경우다
/// (`AuthState.sessionEnded`). 로그인한 적 없는 사람과 달리 이 사람은 자기가
/// 로그인 상태라고 믿고 있으므로, 공개 라우트에 있어도 로그인 화면을 보여 준다.
///
/// 규칙표(테스트가 이 순서대로 잠근다):
///
/// | 상태 | 경로 | 결과 |
/// |:---|:---|:---|
/// | unknown | 아무 데나 | 스플래시 |
/// | unknown | 스플래시 | null |
/// | authenticating | 아무 데나 | null (로그인 화면에 머문다) |
/// | **로그인했고 동의 안 함** | **동의** | **null** |
/// | **로그인했고 동의 안 함** | **그 밖** | **동의** |
/// | onboarding | 온보딩 | null |
/// | onboarding | 그 밖 | 온보딩 |
/// | authenticated | 로그인·가입 | 홈 |
/// | authenticated | 스플래시 | pending ?? 홈 |
/// | authenticated | 그 밖 | null |
/// | unauthenticated + sessionEnded | 아무 데나 | 로그인 |
/// | unauthenticated | 보호 라우트 | 로그인 |
/// | unauthenticated | 공개 라우트 | null |
///
/// [consented] 는 **아직 모를 때 `null`** 이다. 저장소를 읽는 동안이라는 뜻이고, 그때는
/// 아무 데로도 보내지 않는다 — `false` 로 치면 읽는 사이에 동의 화면이 한 번 깜빡이고,
/// `true` 로 치면 그 사이에 동의 없이 앱이 열린다. 둘 다 틀리다.
String? authRedirect({
  required AuthStatus status,
  required String location,
  String? pendingLocation,
  bool sessionEnded = false,
  bool? consented,
}) {
  final path = _pathOf(location);

  // 로그인한 사람이 아직 동의하지 않았으면 **다른 어떤 규칙보다 먼저** 붙잡는다.
  // 온보딩보다 앞인 이유는 반려동물 등록도 개인정보 처리이고, 위치는 그보다 먼저
  // 쓰일 수 있기 때문이다.
  final signedIn =
      status == AuthStatus.authenticated || status == AuthStatus.onboarding;
  if (signedIn && consented == false) {
    return path == consentRoute ? null : consentRoute;
  }
  // 동의를 마쳤는데 동의 화면에 있으면 나간다 — 안 그러면 갇힌다.
  if (signedIn && consented == true && path == consentRoute) return homeRoute;

  switch (status) {
    case AuthStatus.unknown:
      // 아직 모른다. 로그인 화면도 홈도 보여 주면 안 된다 — 둘 중 하나는 틀렸고,
      // 틀린 쪽을 한 프레임 보여 준 뒤 바꾸는 것이 곧 "깜빡임" 이다(완료 조건 7).
      return path == splashRoute ? null : splashRoute;

    case AuthStatus.authenticating:
      // 외부 브라우저가 떠 있다. 화면을 옮기면 돌아올 자리가 사라진다.
      return null;

    case AuthStatus.onboarding:
      // 인증은 됐지만 프로필이 없다. 다른 데로 새지 못하게 붙잡는다.
      return path == onboardingRoute ? null : onboardingRoute;

    case AuthStatus.authenticated:
      if (path == splashRoute) {
        return _settle(status, pendingLocation, sessionEnded: sessionEnded);
      }
      // 이미 로그인했는데 로그인 화면이 뜨면 사용자는 로그인이 풀린 줄 안다.
      if (_authOnlyEntryRoutes.contains(path)) return homeRoute;
      return null;

    case AuthStatus.unauthenticated:
      if (path == splashRoute) {
        return _settle(status, pendingLocation, sessionEnded: sessionEnded);
      }
      // 방금 끝난 세션. 공개 라우트에 있어도 로그인 화면을 보여 준다 —
      // 로그아웃/폐기를 알리지 않으면 사용자는 자기가 나갔다는 것을 모른다.
      if (sessionEnded && path != loginRoute) return loginRoute;
      return isProtectedRoute(path) ? loginRoute : null;
  }
}

/// 스플래시에서 빠져나갈 자리를 고른다.
String _settle(
  AuthStatus status,
  String? pendingLocation, {
  bool sessionEnded = false,
}) {
  if (status != AuthStatus.authenticated && sessionEnded) return loginRoute;
  final target = pendingLocation ?? homeRoute;
  if (_pathOf(target) == splashRoute) return homeRoute; // 스플래시로 되돌아가지 않는다
  if (status != AuthStatus.authenticated && isProtectedRoute(target)) {
    return loginRoute;
  }
  return target;
}

/// 쿼리스트링·프래그먼트를 떼고 경로만 남긴다. `/explore?q=1` 과 `/explore` 는 같은 곳이다.
String _pathOf(String location) {
  final cut = location.indexOf(RegExp(r'[?#]'));
  final path = cut == -1 ? location : location.substring(0, cut);
  // 끝의 슬래시는 무시한다 — '/bookmarks/' 와 '/bookmarks' 가 다르게 판정되면
  // 보호 라우트를 슬래시 하나로 우회할 수 있다.
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/auth_redirect.dart';
import 'package:heat_trip_flutter/app/navigator_keys.dart';
import 'package:heat_trip_flutter/core/widgets/layout/main_nav_shell.dart';
import 'package:heat_trip_flutter/features/bookmark/bookmark_routes.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/consent_gate.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/screens/consent_screen.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';
import 'package:heat_trip_flutter/v2/screens/onboarding_screen.dart';
import 'package:heat_trip_flutter/v2/screens/splash_screen.dart';

// tabs
import 'package:heat_trip_flutter/features/start/start_routes.dart';
import 'package:heat_trip_flutter/features/auth/auth_routes.dart';
import 'package:heat_trip_flutter/features/explore/explore_routes.dart';
import 'package:heat_trip_flutter/features/record/record_routes.dart';
import 'package:heat_trip_flutter/features/journey/journey_routes.dart';
import 'package:heat_trip_flutter/features/profile/profile_routes.dart';

import 'package:heat_trip_flutter/features/foryou_v2/routes.dart';
import 'package:heat_trip_flutter/features/emotion_map/emotion_map_routes.dart';

/// 스플래시로 튕기기 전에 가려던 곳. 상태가 확정되면 여기로 돌려보낸다.
///
/// 라우터 밖의 가변 상태를 하나 두는 것이 마음에 들지는 않지만, 규칙 자체는
/// `auth_redirect.dart` 의 순수 함수에 있고 이 변수는 그 함수의 입력일 뿐이다.
String? _pendingLocation;

/// 지금 로그인한 사람이 약관에 동의했는가. **`null` 이면 아직 모른다**(저장소를 읽는 중).
///
/// `authRedirect` 는 순수 함수라 저장소를 못 읽는다. 그래서 여기서 미리 읽어 두고
/// 값으로 넘긴다 — `_pendingLocation` 과 같은 모양이다.
final ValueNotifier<bool?> _consented = ValueNotifier<bool?>(null);

/// 인증 상태가 바뀌면 동의 여부를 다시 읽는다.
///
/// **계정이 바뀌면 반드시 다시 읽어야 한다.** 앞사람의 값을 그대로 쓰면 뒷사람은
/// 약관을 본 적이 없는데 동의한 것이 된다.
Future<void> _refreshConsent() async {
  final user = AuthState.user;
  final status = AuthState.status.value;
  if (user == null ||
      (status != AuthStatus.authenticated && status != AuthStatus.onboarding)) {
    _consented.value = null;
    // 로그인하지 않은 사람("그냥 둘러보기")은 동의한 적이 없다. 좌표를 얻는 길을
    // 닫는다 — `/explore` 는 공개 라우트라 라우터가 못 붙잡는다. (#180)
    LocationService.consented.value = false;
    return;
  }
  final agreed = await const ConsentGate().hasAgreed(user.id);
  _consented.value = agreed;
  LocationService.consented.value = agreed;
}

/// 라우터를 다시 돌리는 신호 둘을 하나로 묶는다 — 인증 상태와 동의 여부.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh() {
    AuthState.status.addListener(_onAuth);
    _consented.addListener(notifyListeners);
  }

  void _onAuth() {
    // 상태가 바뀌면 동의 여부부터 다시 읽는다. 읽는 동안은 `null` 이라 라우터가
    // 아무 데로도 안 보낸다.
    _refreshConsent();
    notifyListeners();
  }
}

final _routerRefresh = _RouterRefresh();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  // v2 디자인을 정식 진입으로 승격. (구 /start 셸은 아래에 보존 — 로그인/구화면 참조용)
  initialLocation: '/home',

  // 인증 상태가 바뀌면 redirect 를 다시 돌린다. 이것이 없으면 로그아웃해도
  // 보호 라우트에 그대로 남아 있고, 세션 만료(#11)가 화면에 반영되지 않는다.
  refreshListenable: _routerRefresh,

  redirect: (context, state) {
    final here = state.matchedLocation;
    final status = AuthState.status.value;

    // 스플래시로 보내기 직전에 "원래 가려던 곳" 을 기억해 둔다. 기억하지 않으면
    // 딥링크로 들어온 사용자가 검증이 끝난 뒤 무조건 홈으로 떨어진다.
    if (status == AuthStatus.unknown &&
        here != splashRoute &&
        here != loginRoute) {
      _pendingLocation = here;
    }

    final sessionEnded = AuthState.sessionEnded;
    final target = authRedirect(
      status: status,
      location: here,
      pendingLocation: _pendingLocation,
      sessionEnded: sessionEnded,
      consented: _consented.value,
    );

    // 1회성 신호다. 여기서 소비하지 않으면 사용자가 로그인 화면을 닫을 때마다
    // 다시 끌려온다 — go_router 는 redirect 가 null 을 줄 때까지 반복 호출한다.
    if (sessionEnded && target == loginRoute) AuthState.consumeSessionEnded();

    // 스플래시를 벗어나는 순간 기억을 비운다 — 남겨 두면 다음 로그아웃/로그인에서
    // 엉뚱한 옛 목적지로 튄다.
    if (here == splashRoute && status != AuthStatus.unknown) {
      _pendingLocation = null;
    }

    return target;
  },

  routes: [
    GoRoute(
      path: splashRoute,
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: consentRoute,
      name: 'consent',
      builder: (context, state) => ConsentScreen(
        // 여기 닿았다는 것은 이미 로그인했다는 뜻이다(`authRedirect` 가 그렇게 보낸다).
        userId: AuthState.user?.id ?? 0,
        onAgreed: () => _consented.value = true,
      ),
    ),
    GoRoute(
      path: onboardingRoute,
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const MainShell()),
    ...startRoutes,
    ...authRoutes,
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => MainNavShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: buildExploreRoutes()), // 0
        StatefulShellBranch(routes: recordRoutes), // 1 (Schedule, 네비 강등)
        StatefulShellBranch(routes: forYouV2Routes), // 2 오늘
        StatefulShellBranch(routes: journeyRoutes), // 3 피드
        StatefulShellBranch(
          routes: [...profileRoutes, ...bookmarkRoutes],
        ), // 4 나
        StatefulShellBranch(routes: emotionMapRoutes), // 5 감정지도
      ],
    ),
  ],
);

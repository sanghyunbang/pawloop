// lib/features/auth/auth_routes.dart
//
// ## `LoginScreen` 이 두 개인 문제 — 여기서 정본을 정한다 (이슈 #12 · ADR-0022)
//
// 같은 이름의 클래스가 두 파일에 있었고 어느 쪽이 진짜인지 코드만 봐서는 알 수 없었다.
//
//  - `v2/screens/login_screen.dart` — 카카오/구글 소셜 로그인. **정본이다.**
//    제품이 실제로 파는 로그인 경로이고(#3), 라우터의 name `'login'` 이 가리키는 곳이다.
//    `AuthedClient` 의 세션 만료 훅(#11)도 결국 여기로 온다.
//  - `features/auth/presentation/login_screen.dart` — 이메일/비밀번호 로그인.
//    `POST /auth/login` + `POST /auth/signup` 계약(#10)을 쓰는 **개발·QA 전용 경로**다.
//
// ## 이메일 경로는 디버그 빌드에서만 열린다 (ADR-0022)
//
// 정본 로그인 화면에는 이메일로 가는 링크가 없고, 그 화면들은 v1 디자인 그대로다.
// 사용자가 쓰는 로그인은 카카오·구글(iOS 출시 전 Apple 추가)뿐이라고 정했다. 그래도
// 지우지 않는 이유는 통합 테스트와 에뮬레이터 확인이 그 경로로 계정을 만들기 때문이다 —
// `flutter run --route=/auth/sign-up` 으로 연다. 릴리스 빌드에는 라우트 자체가 없다.
//
// 이름이 겹치면 import 두 줄이 서로를 가린다. 그래서 이 파일에서만 별칭을 붙여
// 어느 쪽인지 호출부에서 눈으로 구분되게 한다.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/v2/screens/login_screen.dart' as social;
import 'presentation/login_screen.dart' as email;
import 'presentation/sign_up_screen.dart';

/// 인증 라우트. [emailAuth] 가 false 면 소셜 로그인 하나뿐이다 — 릴리스 빌드의 모양.
///
/// 빌드 모드를 인자로 받는 이유: `kDebugMode` 는 테스트에서 항상 true 라, 상수로만 두면
/// "릴리스에는 이메일 라우트가 없다" 를 테스트가 잴 수 없다.
List<RouteBase> buildAuthRoutes({required bool emailAuth}) => [
      GoRoute(
        path: '/auth/login',
        name: 'login',
        builder: (_, __) => const social.LoginScreen(),
      ),
      if (emailAuth) ...[
        GoRoute(
          path: '/auth/login/email',
          name: 'loginEmail',
          builder: (_, __) => const email.LoginScreen(),
        ),
        GoRoute(
          path: '/auth/sign-up',
          name: 'signUp',
          builder: (_, __) => SignUpScreen(),
        ),
      ],
    ];

/// 앱이 실제로 쓰는 라우트 — 디버그 빌드에서만 이메일 경로가 붙는다.
final List<RouteBase> authRoutes = buildAuthRoutes(emailAuth: kDebugMode);

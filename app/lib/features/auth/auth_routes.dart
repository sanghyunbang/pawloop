// lib/features/auth/auth_routes.dart
//
// ## `LoginScreen` 이 두 개인 문제 — 여기서 정본을 정한다 (이슈 #12)
//
// 같은 이름의 클래스가 두 파일에 있었고 어느 쪽이 진짜인지 코드만 봐서는 알 수 없었다.
//
//  - `v2/screens/login_screen.dart` — 카카오/구글 소셜 로그인. **정본이다.**
//    제품이 실제로 파는 로그인 경로이고(#3), 라우터의 name `'login'` 이 가리키는 곳이다.
//    `AuthedClient` 의 세션 만료 훅(#11)도 결국 여기로 온다.
//  - `features/auth/presentation/login_screen.dart` — 이메일/비밀번호 로그인.
//    `POST /auth/login` + `POST /auth/signup` 계약(#10)을 쓰는 **보조 경로**다.
//    회원가입 화면과 짝이라 지우지 않고 `/auth/login/email` 로 남겨 둔다.
//
// 이름이 겹치면 import 두 줄이 서로를 가린다. 그래서 이 파일에서만 별칭을 붙여
// 어느 쪽인지 호출부에서 눈으로 구분되게 한다.

import 'package:go_router/go_router.dart';

import 'package:heat_trip_flutter/v2/screens/login_screen.dart' as social;
import 'presentation/login_screen.dart' as email;
import 'presentation/sign_up_screen.dart';

final List<RouteBase> authRoutes = [
  GoRoute(
    path: '/auth/login',
    name: 'login',
    builder: (_, __) => const social.LoginScreen(),
  ),
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
];

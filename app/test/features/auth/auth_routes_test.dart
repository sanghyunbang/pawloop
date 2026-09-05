// 이메일 가입·로그인 라우트는 디버그 빌드에만 있다 — ADR-0022.
//
// 사용자가 쓰는 로그인은 카카오·구글뿐이다. 이메일 화면은 v1 잔재이고 진입 링크도 없어서
// 개발·QA 전용으로 두기로 했다. 릴리스에 라우트가 남아 있으면 `/auth/sign-up` 을 URL 로 열어
// 정본이 아닌 가입 경로가 살아난다.

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/features/auth/auth_routes.dart';

Iterable<String> _paths(List<RouteBase> routes) =>
    routes.whereType<GoRoute>().map((r) => r.path);

void main() {
  test('릴리스 모양(emailAuth: false)에는 소셜 로그인 하나뿐이다', () {
    final paths = _paths(buildAuthRoutes(emailAuth: false)).toList();

    expect(paths, ['/auth/login']);
    expect(paths, isNot(contains('/auth/sign-up')),
        reason: '릴리스에 남으면 URL 로 열리는 가입 경로가 생긴다 — 정본은 소셜뿐이다(ADR-0022)');
    expect(paths, isNot(contains('/auth/login/email')));
  });

  test('디버그 모양(emailAuth: true)에는 이메일 로그인·가입이 붙는다 — 테스트와 에뮬레이터가 쓴다', () {
    final paths = _paths(buildAuthRoutes(emailAuth: true)).toList();

    expect(paths, ['/auth/login', '/auth/login/email', '/auth/sign-up']);
  });

  test('정본 로그인의 이름은 login 이다 — 세션 만료 훅과 라우터가 그 이름으로 온다', () {
    final login = buildAuthRoutes(emailAuth: false).whereType<GoRoute>().single;
    expect(login.name, 'login');
  });
}

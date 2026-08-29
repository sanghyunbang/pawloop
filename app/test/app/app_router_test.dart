// 라우터 인증 가드 — `authRedirect` 순수 함수 표 검증 (이슈 #12).
//
// `GoRouter` 를 세우지 않는다. 규칙은 `(상태, 경로) → 경로?` 일 뿐이고,
// 라우터를 세우면 화면·Provider·지도 SDK 까지 딸려온다. 규칙만 시험한다(정책 #21).

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/app/auth_redirect.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';

void main() {
  group('unknown — 스플래시 구간', () {
    test('어디로 가려 하든 스플래시로 보낸다', () {
      for (final location in ['/home', '/explore', '/bookmarks', loginRoute]) {
        expect(
          authRedirect(status: AuthStatus.unknown, location: location),
          splashRoute,
          reason: '$location 에서 스플래시로 가야 한다',
        );
      }
    });

    test('이미 스플래시면 리다이렉트하지 않는다 — 무한 루프 방지', () {
      expect(
        authRedirect(status: AuthStatus.unknown, location: splashRoute),
        isNull,
      );
    });
  });

  group('unauthenticated — 둘러보기는 막지 않는다', () {
    test('보호 라우트는 로그인으로 보낸다', () {
      for (final location in [
        '/profile/edit',
        '/bookmarks',
        '/bookmarks/collections/3',
        '/record/create',
        onboardingRoute,
      ]) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
          ),
          loginRoute,
          reason: '$location 은 내 데이터라 로그인이 필요하다',
        );
      }
    });

    test('공개 라우트는 그대로 둔다 — "그냥 둘러보기" 가 성립해야 한다', () {
      for (final location in [
        '/home',
        '/explore',
        '/explore/123/12',
        '/discover',
        '/emotion_map',
        '/journey',
        '/foryou_v2',
        '/profile',
        '/start',
        loginRoute,
        '/auth/sign-up',
      ]) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
          ),
          isNull,
          reason: '$location 은 로그인 없이 볼 수 있어야 한다',
        );
      }
    });

    test('끝의 슬래시로 보호 라우트를 우회할 수 없다', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/bookmarks/',
        ),
        loginRoute,
      );
    });

    test('쿼리스트링이 붙어도 같은 경로로 판정한다', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/bookmarks?tab=all',
        ),
        loginRoute,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/explore?q=%EC%84%9C%EC%9A%B8',
        ),
        isNull,
      );
    });

    test('/profile 은 공개지만 /profile/edit 은 보호된다 — 접두사 오판 방지', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/profile',
        ),
        isNull,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/profile/edit',
        ),
        loginRoute,
      );
    });
  });

  group('authenticated', () {
    test('로그인 화면에 머무를 이유가 없다 — 홈으로 보낸다', () {
      expect(
        authRedirect(status: AuthStatus.authenticated, location: loginRoute),
        homeRoute,
      );
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: '/auth/sign-up',
        ),
        homeRoute,
      );
    });

    test('보호 라우트도 공개 라우트도 그대로 연다', () {
      for (final location in ['/home', '/bookmarks', '/profile/edit']) {
        expect(
          authRedirect(status: AuthStatus.authenticated, location: location),
          isNull,
        );
      }
    });
  });

  group('스플래시에서 빠져나가기', () {
    test('가려던 곳이 없으면 홈으로', () {
      expect(
        authRedirect(status: AuthStatus.authenticated, location: splashRoute),
        homeRoute,
      );
    });

    test('가려던 곳으로 돌려보낸다 — 딥링크가 홈으로 떨어지지 않게', () {
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: splashRoute,
          pendingLocation: '/explore/999/12',
        ),
        '/explore/999/12',
      );
    });

    test('로그인이 아닌데 가려던 곳이 보호 라우트면 로그인으로', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          pendingLocation: '/bookmarks',
        ),
        loginRoute,
      );
    });

    test('로그인이 아니어도 가려던 곳이 공개면 그리로', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          pendingLocation: '/explore',
        ),
        '/explore',
      );
    });

    test('스플래시로 되돌아가지 않는다', () {
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: splashRoute,
          pendingLocation: splashRoute,
        ),
        homeRoute,
      );
    });
  });

  group('onboarding — 신규 가입자를 붙잡는다', () {
    test('온보딩 화면 밖으로 나가려 하면 다시 온보딩으로', () {
      for (final location in ['/home', '/explore', loginRoute, splashRoute]) {
        expect(
          authRedirect(status: AuthStatus.onboarding, location: location),
          onboardingRoute,
          reason: '$location 으로 새면 프로필 없는 계정이 앱을 돌아다닌다',
        );
      }
    });

    test('온보딩 화면 자체는 그대로 둔다', () {
      expect(
        authRedirect(
          status: AuthStatus.onboarding,
          location: onboardingRoute,
        ),
        isNull,
      );
    });
  });

  group('authenticating — 외부 브라우저 왕복 중', () {
    test('화면을 옮기지 않는다 — 돌아올 자리를 없애면 안 된다', () {
      for (final location in ['/home', loginRoute, '/bookmarks']) {
        expect(
          authRedirect(status: AuthStatus.authenticating, location: location),
          isNull,
        );
      }
    });
  });

  // 로그인한 적 없는 사람과 방금 로그아웃당한 사람은 같은 unauthenticated 지만
  // 보여 줄 화면이 다르다. 후자는 자기가 로그인 상태라고 믿고 있다.
  group('sessionEnded — 방금 끝난 세션 (완료 조건 4·6)', () {
    test('공개 라우트에 있어도 로그인 화면으로 보낸다', () {
      for (final location in ['/home', '/explore', '/profile']) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
            sessionEnded: true,
          ),
          loginRoute,
          reason: '$location 에서 조용히 로그아웃되면 사용자가 알 방법이 없다',
        );
      }
    });

    test('이미 로그인 화면이면 리다이렉트하지 않는다 — 무한 루프 방지', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: loginRoute,
          sessionEnded: true,
        ),
        isNull,
      );
    });

    test('폐기된 토큰으로 앱을 켜면 스플래시에서 홈이 아니라 로그인으로 나간다', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          pendingLocation: '/home',
          sessionEnded: true,
        ),
        loginRoute,
      );
    });

    test('신호가 없으면(=한 번도 로그인한 적 없음) 공개 라우트는 그대로다', () {
      expect(
        authRedirect(status: AuthStatus.unauthenticated, location: '/home'),
        isNull,
      );
    });
  });

  group('isProtectedRoute', () {
    test('목록에 적힌 것과 그 하위만 보호된다', () {
      expect(isProtectedRoute('/bookmarks'), isTrue);
      expect(isProtectedRoute('/bookmarks/collections/1'), isTrue);
      expect(isProtectedRoute('/bookmarksomething'), isFalse,
          reason: '접두사 문자열이 아니라 경로 세그먼트로 판정해야 한다');
      expect(isProtectedRoute('/home'), isFalse);
    });
  });
}

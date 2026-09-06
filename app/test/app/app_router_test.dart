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
      for (final location in ['/home', onboardingRoute, '/home?tab=1', loginRoute]) {
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
      // 라우트로 존재하는 보호 화면은 온보딩뿐이다 — 레거시 셸의 보호 라우트는 #94 로 지웠다.
      for (final location in [
        onboardingRoute,
        '$onboardingRoute/step-2',
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
        '/home?tab=1',
        loginRoute,
        '/auth/sign-up',
        '/auth/login/email',
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
          location: '$onboardingRoute/',
        ),
        loginRoute,
      );
    });

    test('쿼리스트링이 붙어도 같은 경로로 판정한다', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '$onboardingRoute?step=2',
        ),
        loginRoute,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/home?q=%EC%84%9C%EC%9A%B8',
        ),
        isNull,
      );
    });

    test('/onboarding-guide 는 공개지만 /onboarding 은 보호된다 — 접두사 오판 방지', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '$onboardingRoute-guide',
        ),
        isNull,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: onboardingRoute,
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
      for (final location in ['/home', onboardingRoute]) {
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
          pendingLocation: '/home?tab=1',
        ),
        '/home?tab=1',
      );
    });

    test('로그인이 아닌데 가려던 곳이 보호 라우트면 로그인으로', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          pendingLocation: onboardingRoute,
        ),
        loginRoute,
      );
    });

    test('로그인이 아니어도 가려던 곳이 공개면 그리로', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          pendingLocation: '/home?tab=1',
        ),
        '/home?tab=1',
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
      for (final location in ['/home', '/home?tab=1', loginRoute, splashRoute]) {
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
      for (final location in ['/home', loginRoute, onboardingRoute]) {
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
      for (final location in ['/home', '/home?tab=1', '/auth/sign-up']) {
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
      expect(isProtectedRoute(onboardingRoute), isTrue);
      expect(isProtectedRoute('$onboardingRoute/step-2'), isTrue);
      expect(isProtectedRoute('${onboardingRoute}something'), isFalse,
          reason: '접두사 문자열이 아니라 경로 세그먼트로 판정해야 한다');
      expect(isProtectedRoute('/home'), isFalse);
    });
  });

  // ─────────────── 약관 동의 게이트 (#180) ───────────────
  //
  // v2 에는 동의를 받는 자리가 하나도 없었다. 로그인은 소셜뿐이고 그 흐름에 약관을
  // 보여 주는 화면이 없다. 즉 이 앱은 아무 동의 없이 위치를 수집하고 있었다.

  group('동의 전에는 앱을 못 쓴다', () {
    test('로그인했는데 동의를 안 했으면 어디로 가든 동의 화면이다', () {
      for (final where in [homeRoute, onboardingRoute, '/home?tab=1', loginRoute]) {
        expect(
          authRedirect(
            status: AuthStatus.authenticated,
            location: where,
            consented: false,
          ),
          consentRoute,
          reason: '$where 에서 새면 동의 없이 위치가 수집된다',
        );
      }
    });

    test('온보딩보다 앞이다 — 반려동물 등록도 개인정보 처리다', () {
      expect(
        authRedirect(
          status: AuthStatus.onboarding,
          location: onboardingRoute,
          consented: false,
        ),
        consentRoute,
      );
    });

    test('동의 화면에서는 안 튕긴다 — 튕기면 무한 반복이다', () {
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: consentRoute,
          consented: false,
        ),
        isNull,
      );
    });

    test('동의를 마치면 동의 화면에서 나간다 — 안 나가면 갇힌다', () {
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: consentRoute,
          consented: true,
        ),
        homeRoute,
      );
    });

    test('아직 모를 때(null)는 아무 데로도 안 보낸다', () {
      // 저장소를 읽는 중이다. false 로 치면 화면이 깜빡이고, true 로 치면 그 사이에
      // 동의 없이 앱이 열린다. 둘 다 틀리다.
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: homeRoute,
          consented: null,
        ),
        isNull,
      );
    });

    test('로그인 안 한 사람은 동의 화면으로 안 간다 — 누구의 동의인지 정할 수 없다', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/home?tab=1',
          consented: false,
        ),
        isNull,
      );
    });

    test('동의를 마쳤으면 예전 규칙이 그대로 돈다', () {
      expect(
        authRedirect(
          status: AuthStatus.onboarding,
          location: homeRoute,
          consented: true,
        ),
        onboardingRoute,
      );
      expect(
        authRedirect(
          status: AuthStatus.authenticated,
          location: loginRoute,
          consented: true,
        ),
        homeRoute,
      );
    });
  });

  // 첫 실행 소개(#323) — 로그인한 적 없는 기기에서 한 번, 로그인 화면보다 앞.
  group('intro — 첫 실행 소개', () {
    test('소개를 안 봤으면 어디로 가려 하든 소개로', () {
      for (final location in [
        splashRoute,
        '/home',
        '/home?tab=1',
        loginRoute,
        '/auth/sign-up',
      ]) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
            introSeen: false,
          ),
          introRoute,
          reason: '$location — 앱이 무엇인지 모른 채 시작하면 안 된다',
        );
      }
    });

    test('소개 화면 자체는 그대로 둔다 — 무한 루프 방지', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: introRoute,
          introSeen: false,
        ),
        isNull,
      );
    });

    test('봤는지 모르면 움직이지 않는다 — 깜빡임도 건너뜀도 아니다', () {
      for (final location in [splashRoute, '/home', loginRoute]) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
            introSeen: null,
          ),
          isNull,
          reason: location,
        );
      }
    });

    test('봤으면 지금 규칙 그대로 — 스플래시는 홈으로, 공개 라우트는 그대로', () {
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: splashRoute,
          introSeen: true,
        ),
        homeRoute,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: '/home',
          introSeen: true,
        ),
        isNull,
      );
      expect(
        authRedirect(
          status: AuthStatus.unauthenticated,
          location: introRoute,
          introSeen: true,
        ),
        isNull,
        reason: '설정에서 다시 보는 길을 막지 않는다',
      );
    });

    test('방금 끝난 세션은 소개를 다시 보지 않는다 — 로그인으로', () {
      for (final location in [splashRoute, '/home', introRoute]) {
        expect(
          authRedirect(
            status: AuthStatus.unauthenticated,
            location: location,
            sessionEnded: true,
            introSeen: false,
          ),
          loginRoute,
          reason: '$location — 이 사람은 앱이 무엇인지 이미 안다',
        );
      }
    });

    test('로그인한 사람이 소개로 들어오면 홈으로', () {
      for (final seen in [false, true]) {
        expect(
          authRedirect(
            status: AuthStatus.authenticated,
            location: introRoute,
            introSeen: seen,
          ),
          homeRoute,
          reason: 'introSeen=$seen',
        );
      }
    });

    test('소개 라우트는 공개다 — 보호 목록에 없다', () {
      expect(isProtectedRoute(introRoute), isFalse);
    });
  });

}

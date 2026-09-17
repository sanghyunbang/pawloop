// 소셜 로그인 콜백 딥링크 판정 — 순수 함수 테스트. (이슈 #14)
//
// flutter_web_auth_2 가 돌려주는 URL 문자열만 다룬다 — 네트워크도, 플랫폼 채널도,
// 저장소도 타지 않으므로 비행기 모드에서도 돈다. 테스트 정책은 이슈 #21 참조.
//
// ## 왜 파일 전체가 바뀌었나
//
// #14 이전 딥링크는 `?token=<AT>&refresh=<RT>` 였고 이 파일은 그 세 파라미터
// (`token`·`refresh`·`isNew`)를 뽑는 함수들을 잠그고 있었다. 지금 딥링크에는
// **코드와 state 만** 실린다. 옛 함수들은 오지 않는 값을 찾는 코드라 지웠다 —
// 남겨 두면 "테스트가 있는 죽은 코드" 가 되고, 그건 초록불이 거짓말을 하는 형태다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';

/// 이 테스트 전반에서 "앱이 만들어 저장해 둔 값" 역할.
const _state = 'st-ABCdef123_-';

void main() {
  group('newOAuthState', () {
    test('딥링크 쿼리에 그대로 실어도 되는 문자만 쓴다', () {
      // 백엔드의 OAuthAppStateFilter 화이트리스트와 같은 규칙이다.
      // `&` 한 글자가 섞이면 딥링크에 파라미터를 하나 더 만든다.
      expect(newOAuthState(), matches(r'^[A-Za-z0-9_-]{16,128}$'));
    });

    test('부를 때마다 다른 값이다 — 고정값이면 대조가 통과 의식일 뿐이다', () {
      final values = List.generate(20, (_) => newOAuthState()).toSet();

      expect(values.length, 20);
    });

    test('기본 난수원이 Random.secure 다 — 소스를 직접 읽어 잠근다', () {
      // 위 두 테스트는 `Random.secure()` 를 예측 가능한 `Random()` 으로 낮춰도 **둘 다
      // 초록이다**(실측: 185/185 통과). 정규식도, 20개가 서로 다르다는 것도 비암호학적
      // PRNG 가 만족한다. 그리고 `newOAuthState([Random? random])` 의 주입점으로는
      // **기본값**을 검사할 수 없다 — 주입하는 순간 기본값을 지나가지 않기 때문이다.
      //
      // 그래서 소스를 읽는다. 이 저장소에는 no_token_logging_test.dart 라는 같은 형태의
      // 소스 검사 테스트가 이미 있다. 이 값이 예측 가능해지는 순간 state 대조는 문자
      // 그대로 통과 의식이 된다.
      final source = File('lib/features/auth/service/oauth_callback.dart')
          .readAsStringSync();

      expect(
        source,
        contains('random ?? Random.secure()'),
        reason: '기본 난수원이 Random.secure 가 아니면 state 를 공격자가 예측할 수 있다',
      );
    });
  });

  group('codeFromCallback', () {
    test('정상 콜백 URL에서 code 파라미터를 그대로 뽑는다', () {
      const url = 'pawloop://login-callback?code=abcDEF123&state=$_state';

      expect(codeFromCallback(url), 'abcDEF123');
    });

    test('code 가 없거나 공백뿐이면 null 이다', () {
      expect(codeFromCallback('pawloop://login-callback?state=$_state'), isNull);
      expect(codeFromCallback('pawloop://login-callback?code='), isNull);
      expect(codeFromCallback('pawloop://login-callback?code=%20'), isNull);
    });

    test('URL 형식이 깨져도 예외를 던지지 않고 null 을 돌려준다', () {
      expect(codeFromCallback('http://[invalid'), isNull);
      expect(codeFromCallback(''), isNull);
    });

    test('깨진 퍼센트 인코딩에도 던지지 않는다 — Uri.parse 는 통과시키고 디코딩이 던진다', () {
      // Uri.parse 는 깨진 이스케이프를 그 자리에서 거부하지 않는다. queryParameters 가
      // **접근 시점에 지연 디코딩**하며 FormatException 을 던진다. 실측:
      //   FormatException: Missing extension byte (at offset 2)
      expect(
        codeFromCallback(
            'pawloop://login-callback?code=C&state=$_state&x=%E0%A4%A'),
        isNull,
      );
    });
  });

  group('resolveOAuthCallback — 정상', () {
    test('state 가 일치하고 code 가 있으면 성공이고 code 를 돌려준다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123&state=$_state',
        _state,
      );

      expect(result.outcome, SocialLoginOutcome.success);
      expect(result.ok, isTrue);
      expect(result.code, 'abcDEF123');
    });

    test('파라미터 순서가 바뀌어도 판정은 같다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?state=$_state&code=abcDEF123',
        _state,
      );

      expect(result.code, 'abcDEF123');
    });
  });

  group('resolveOAuthCallback — state 대조 (완료 조건 4)', () {
    test('state 가 다르면 실패다 — 응답 바꿔치기를 막는 장치가 이것뿐이다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123&state=someone-elses-state',
        _state,
      );

      expect(result.ok, isFalse);
      expect(result.outcome, SocialLoginOutcome.serverError);
      expect(
        result.code,
        isNull,
        reason: '실패한 판정이 code 를 돌려주면 호출부가 그걸 교환에 쓸 수 있다',
      );
    });

    test('state 가 아예 없으면 실패다 — 없는 것은 일치가 아니다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123',
        _state,
      );

      expect(result.ok, isFalse);
    });

    test('state 가 비어 있으면 실패다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123&state=',
        _state,
      );

      expect(result.ok, isFalse);
    });

    test('대소문자가 다르면 실패다 — 느슨한 비교는 비교가 아니다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123&state=${_state.toUpperCase()}',
        _state,
      );

      expect(result.ok, isFalse);
    });

    test('기대하는 state 자체가 비어 있으면 성공시키지 않는다', () {
      // 앱이 state 생성을 건너뛴 상태를 조용히 통과시키면 검사가 있다고 말할 수 없다.
      final result = resolveOAuthCallback(
        'pawloop://login-callback?code=abcDEF123&state=',
        '',
      );

      expect(result.ok, isFalse);
    });
  });

  group('resolveOAuthCallback — code 없음', () {
    test('code 가 없으면 실패다 — 계약 위반이지 사용자 탓이 아니다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?state=$_state',
        _state,
      );

      expect(result.outcome, SocialLoginOutcome.serverError);
      expect(result.code, isNull);
    });

    test('URL 형식이 깨져도 예외를 던지지 않는다', () {
      expect(resolveOAuthCallback('http://[invalid', _state).outcome,
          SocialLoginOutcome.serverError);
      expect(resolveOAuthCallback('', _state).outcome,
          SocialLoginOutcome.serverError);
    });

    test('깨진 퍼센트 인코딩은 serverError 로 떨어진다 — 예외로 새 나가지 않는다', () {
      // 이 함수는 "순수 함수" 라고 선언돼 있는데 여기서 FormatException 을 밖으로
      // 던지고 있었다. SocialLoginService.signIn 은 이 호출을 try/catch 로 감싸지
      // 않아서(앞뒤의 authenticator·exchanger·saveTokens 는 감싼다) 그 예외는
      // SocialLoginResult 로 분류되지 못하고 **처리되지 않은 비동기 오류**가 됐다 —
      // 사용자에게는 아무 반응 없는 버튼으로 보인다.
      const broken =
          'pawloop://login-callback?code=C&state=$_state&x=%E0%A4%A';

      expect(
        () => resolveOAuthCallback(broken, _state),
        returnsNormally,
        reason: '순수 함수가 결말 대신 예외를 내보내면 호출부가 그것을 분류할 자리가 없다',
      );
      expect(resolveOAuthCallback(broken, _state).outcome,
          SocialLoginOutcome.serverError);
    });
  });

  group('resolveOAuthCallback — error 딥링크', () {
    test('취소 계열 error 는 canceled 다 — state 대조보다 먼저 본다', () {
      // 취소 딥링크에는 state 가 실려 오지 않는다. state 를 먼저 보면 스스로 창을
      // 닫은 사용자에게 "서버에 문제가 있다" 고 말하게 된다.
      for (final code in [
        'access_denied',
        'user_cancelled',
        'user_canceled',
        'cancelled',
        'canceled',
      ]) {
        expect(
          resolveOAuthCallback('pawloop://login-callback?error=$code', _state)
              .outcome,
          SocialLoginOutcome.canceled,
          reason: '$code 는 취소로 분류돼야 한다',
        );
      }
    });

    test('그 밖의 error 는 serverError 다', () {
      expect(
        resolveOAuthCallback(
          'pawloop://login-callback?error=account_state_invalid',
          _state,
        ).outcome,
        SocialLoginOutcome.serverError,
      );
      expect(
        resolveOAuthCallback(
          'pawloop://login-callback?error=email_already_registered',
          _state,
        ).outcome,
        SocialLoginOutcome.serverError,
      );
    });

    test('error 와 code 가 함께 와도 실패로 본다', () {
      final result = resolveOAuthCallback(
        'pawloop://login-callback?error=access_denied&code=abc&state=$_state',
        _state,
      );

      expect(result.ok, isFalse);
      expect(result.code, isNull);
    });
  });

  // 예외 분류는 #12 에서 들어온 규칙 그대로다 — 딥링크 모양이 바뀌어도 변하지 않는다.
  group('outcomeFromError', () {
    test('사용자가 브라우저를 닫으면 canceled 다', () {
      for (final code in ['CANCELED', 'CANCELLED', 'USER_CANCELED']) {
        expect(
          outcomeFromError(PlatformException(code: code)),
          SocialLoginOutcome.canceled,
        );
      }
    });

    test('네트워크 계열 예외는 networkError 다', () {
      expect(outcomeFromError(const SocketException('no route')),
          SocialLoginOutcome.networkError);
      expect(outcomeFromError(http.ClientException('boom')),
          SocialLoginOutcome.networkError);
      expect(outcomeFromError(TimeoutException('slow')),
          SocialLoginOutcome.networkError);
    });

    test('그 밖의 예외는 serverError 다', () {
      expect(outcomeFromError(PlatformException(code: 'UNKNOWN')),
          SocialLoginOutcome.serverError);
      expect(outcomeFromError(StateError('boom')),
          SocialLoginOutcome.serverError);
    });
  });
}

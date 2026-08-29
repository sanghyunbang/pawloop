// 소셜 로그인 콜백 딥링크 파싱 순수 함수 테스트.
//
// flutter_web_auth_2 가 돌려주는 URL 문자열만 다룬다 — 네트워크도, 플러그인도,
// 저장소도 타지 않으므로 비행기 모드에서도 돈다. 테스트 정책은 이슈 #21 참조.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';

void main() {
  group('tokenFromCallback', () {
    test('정상 콜백 URL에서 token 파라미터를 그대로 뽑는다', () {
      const url =
          'heattrip://login-callback?token=eyJhbGciOiJIUzI1NiJ9.payload.sig';

      expect(
        tokenFromCallback(url),
        'eyJhbGciOiJIUzI1NiJ9.payload.sig',
      );
    });

    test('다른 파라미터가 섞여 있어도 token만 골라낸다', () {
      const url =
          'heattrip://login-callback?provider=google&token=abc.def.ghi&state=xyz';

      expect(tokenFromCallback(url), 'abc.def.ghi');
    });

    test('token 파라미터가 없는 URL은 null을 돌려준다', () {
      expect(tokenFromCallback('heattrip://login-callback'), isNull);
      expect(tokenFromCallback('heattrip://login-callback?state=xyz'), isNull);
    });

    test('사용자가 동의를 거부한 error 콜백은 null을 돌려준다', () {
      expect(
        tokenFromCallback('heattrip://login-callback?error=access_denied'),
        isNull,
      );
    });

    test('error와 token이 함께 와도 실패로 본다', () {
      expect(
        tokenFromCallback(
          'heattrip://login-callback?error=access_denied&token=abc',
        ),
        isNull,
      );
    });

    test('token 값이 비어 있으면 null을 돌려준다', () {
      expect(tokenFromCallback('heattrip://login-callback?token='), isNull);
      expect(tokenFromCallback('heattrip://login-callback?token=%20'), isNull);
    });

    test('URL 형식이 깨져도 예외를 던지지 않고 null을 돌려준다', () {
      expect(tokenFromCallback('http://[invalid'), isNull);
      expect(tokenFromCallback(''), isNull);
    });
  });

  // #9 부터 딥링크는 `?token=<AT>&refresh=<RT>` 다. 그전까지 앱은 refresh 를
  // 버렸고, 그래서 AT 가 만료되는 순간 사용자는 조용히 로그아웃됐다.
  group('refreshFromCallback', () {
    test('token 과 refresh 가 함께 온 콜백에서 refresh 만 뽑는다', () {
      const url =
          'heattrip://login-callback?token=eyJhbGciOiJIUzI1NiJ9.p.s&refresh=abcdefRT';

      expect(refreshFromCallback(url), 'abcdefRT');
      expect(tokenFromCallback(url), 'eyJhbGciOiJIUzI1NiJ9.p.s');
    });

    test('파라미터 순서가 바뀌어도 값을 그대로 뽑는다', () {
      const url = 'heattrip://login-callback?refresh=RT-1&token=AT-1&state=xyz';

      expect(refreshFromCallback(url), 'RT-1');
    });

    test('refresh 가 없는 옛 딥링크는 null 이다 — 로그인 자체는 실패가 아니다', () {
      const url = 'heattrip://login-callback?token=AT-1';

      expect(refreshFromCallback(url), isNull);
      expect(tokenFromCallback(url), 'AT-1', reason: 'AT 만으로도 로그인은 성립한다');
    });

    test('error 콜백은 refresh 도 실패로 본다', () {
      expect(
        refreshFromCallback(
          'heattrip://login-callback?error=access_denied&refresh=RT-1',
        ),
        isNull,
      );
    });

    test('refresh 값이 비었거나 URL 이 깨져도 예외 없이 null 이다', () {
      expect(refreshFromCallback('heattrip://login-callback?refresh='), isNull);
      expect(
        refreshFromCallback('heattrip://login-callback?refresh=%20'),
        isNull,
      );
      expect(refreshFromCallback('http://[invalid'), isNull);
      expect(refreshFromCallback(''), isNull);
    });

    test('퍼센트 인코딩된 refresh 값을 디코드해 돌려준다', () {
      // 불투명 문자열이라 파싱하지 않지만, URL 디코드는 Uri 가 이미 해 준다.
      expect(
        refreshFromCallback('heattrip://login-callback?refresh=a%2Bb%2Fc'),
        'a+b/c',
      );
    });
  });

  group('isNewFromCallback (이슈 #12)', () {
    test('isNew=true 면 참이다 — 신규 가입자를 온보딩으로 보내는 근거', () {
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&isNew=true'),
        isTrue,
      );
    });

    test('대소문자를 가리지 않고 1 도 참으로 본다', () {
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&isNew=TRUE'),
        isTrue,
      );
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&isNew=1'),
        isTrue,
      );
    });

    test('파라미터가 아예 없으면 false — 지금 백엔드가 이 경우다', () {
      // 재로그인마다 온보딩이 다시 뜨면 매번 반려동물 프로필을 새로 등록하라는 앱이 된다.
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&refresh=RT'),
        isFalse,
      );
    });

    test('false·빈 값·깨진 URL 은 전부 false 다', () {
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&isNew=false'),
        isFalse,
      );
      expect(
        isNewFromCallback('heattrip://login-callback?token=AT&isNew='),
        isFalse,
      );
      expect(isNewFromCallback('http://[invalid'), isFalse);
      expect(isNewFromCallback(''), isFalse);
    });
  });

  group('outcomeFromCallback — 실패 사유 분기 (이슈 #12 완료 조건 9)', () {
    test('token 이 있으면 성공이다', () {
      expect(
        outcomeFromCallback('heattrip://login-callback?token=AT&refresh=RT'),
        SocialLoginOutcome.success,
      );
    });

    test('access_denied 는 서버 오류가 아니라 사용자 취소다', () {
      for (final code in [
        'access_denied',
        'user_cancelled',
        'USER_CANCELED',
        'cancelled',
      ]) {
        expect(
          outcomeFromCallback('heattrip://login-callback?error=$code'),
          SocialLoginOutcome.canceled,
          reason: '$code 는 사용자가 스스로 그만둔 것이다',
        );
      }
    });

    test('그 밖의 error 는 서버 오류다', () {
      expect(
        outcomeFromCallback(
          'heattrip://login-callback?error=account_state_invalid',
        ),
        SocialLoginOutcome.serverError,
      );
    });

    test('error 도 token 도 없는 콜백은 계약 위반 — 서버 오류로 본다', () {
      expect(
        outcomeFromCallback('heattrip://login-callback'),
        SocialLoginOutcome.serverError,
      );
      expect(outcomeFromCallback('http://[invalid'), SocialLoginOutcome.serverError);
    });
  });

  group('outcomeFromError — 예외를 사유로 분류한다', () {
    test('PlatformException(CANCELED) 는 취소다', () {
      // flutter_web_auth_2 는 사용자가 브라우저 탭을 닫으면 이 예외를 던진다.
      expect(
        outcomeFromError(PlatformException(code: 'CANCELED')),
        SocialLoginOutcome.canceled,
      );
      expect(
        outcomeFromError(PlatformException(code: 'cancelled')),
        SocialLoginOutcome.canceled,
      );
    });

    test('그 밖의 PlatformException 은 서버 오류다', () {
      expect(
        outcomeFromError(PlatformException(code: 'NO_BROWSER')),
        SocialLoginOutcome.serverError,
      );
    });

    test('소켓·클라이언트·타임아웃 예외는 네트워크 오류다', () {
      expect(
        outcomeFromError(const SocketException('no route')),
        SocialLoginOutcome.networkError,
      );
      expect(
        outcomeFromError(http.ClientException('failed')),
        SocialLoginOutcome.networkError,
      );
      expect(
        outcomeFromError(TimeoutException('too slow')),
        SocialLoginOutcome.networkError,
      );
    });

    test('알 수 없는 예외는 서버 오류로 떨어뜨린다', () {
      expect(outcomeFromError(StateError('?')), SocialLoginOutcome.serverError);
    });
  });
}

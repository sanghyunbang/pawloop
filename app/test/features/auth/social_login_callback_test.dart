// 소셜 로그인 콜백 딥링크 파싱 순수 함수 테스트.
//
// flutter_web_auth_2 가 돌려주는 URL 문자열만 다룬다 — 네트워크도, 플러그인도,
// 저장소도 타지 않으므로 비행기 모드에서도 돈다. 테스트 정책은 이슈 #21 참조.
import 'package:flutter_test/flutter_test.dart';
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
}

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
}

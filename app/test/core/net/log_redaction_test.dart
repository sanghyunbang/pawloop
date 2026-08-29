// 로그 마스킹 규칙 — 이슈 #61.
//
// 백엔드는 #6 에서 "토큰·시크릿·이메일을 어떤 로그 레벨에도 남기지 않는다" 를 세우고
// OAuthLoggingHygieneTest 로 잠갔다. 프론트에는 그 규칙도 그 잠금도 없었고,
// 그래서 KTO 서비스키가 URL 째로 플랫폼 로그에 남고 있었다.
//
// 이 테스트가 그 잠금이다. 마스킹을 지우면 여기서 빨간불이 난다.

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/log_redaction.dart';

void main() {
  group('URL 마스킹', () {
    test('KTO 서비스키는 값이 남지 않는다 — 실제로 새고 있던 경로다', () {
      final url = Uri.https('apis.data.go.kr', '/B551011/KorService2/detailCommon2', {
        'serviceKey': 'REAL-KTO-KEY-abcdef123456',
        'MobileOS': 'ETC',
        'contentId': '126508',
      });

      final logged = redactUrl(url);

      expect(logged, isNot(contains('REAL-KTO-KEY-abcdef123456')),
          reason: '이 키는 쿼리스트링으로 흐른다. URL 을 찍는 순간 로그로 샌다');
      expect(logged, contains(redactedMark));
    });

    test('비밀이 아닌 파라미터와 경로는 그대로 남는다 — 디버깅이 가능해야 한다', () {
      final url = Uri.https('apis.data.go.kr', '/B551011/KorService2/detailCommon2', {
        'serviceKey': 'secret',
        'contentId': '126508',
      });

      final logged = redactUrl(url);

      expect(logged, contains('detailCommon2'));
      expect(logged, contains('126508'));
    });

    test('토큰류 파라미터 이름은 대소문자를 가리지 않고 가린다', () {
      for (final name in ['token', 'TOKEN', 'access_token', 'refreshToken', 'code']) {
        final url = Uri.https('example.com', '/cb', {name: 'LEAKED'});
        expect(redactUrl(url), isNot(contains('LEAKED')), reason: '파라미터 이름: $name');
      }
    });

    test('쿼리가 없으면 URL 을 그대로 돌려준다', () {
      final url = Uri.https('example.com', '/health');
      expect(redactUrl(url), 'https://example.com/health');
    });
  });

  group('헤더 마스킹', () {
    test('Authorization 은 값이 남지 않는다', () {
      const jwt = 'Bearer eyJhbGciOiJIUzI1NiJ9.PAYLOAD.SIGNATURE';

      expect(redactHeader('Authorization', jwt), isNot(contains('SIGNATURE')));
      expect(redactHeader('authorization', jwt), isNot(contains('SIGNATURE')),
          reason: 'HTTP 헤더 이름은 대소문자를 가리지 않는다');
      expect(redactHeader('Authorization', jwt), contains(redactedMark));
    });

    test('Cookie 계열도 가린다', () {
      expect(redactHeader('Cookie', 'session=SECRET'), isNot(contains('SECRET')));
      expect(redactHeader('Set-Cookie', 'session=SECRET'), isNot(contains('SECRET')));
    });

    test('비밀이 아닌 헤더는 그대로 남는다', () {
      expect(redactHeader('Content-Type', 'application/json'),
          'Content-Type: application/json');
    });
  });

  group('본문 마스킹', () {
    test('로그인 응답의 토큰이 남지 않는다', () {
      const body = '{"token":"eyJhbGciOiJIUzI1NiJ9.PAYLOAD.SIG","isNew":false}';

      final logged = redactBody(body);

      expect(logged, isNot(contains('PAYLOAD')));
      expect(logged, contains('isNew'), reason: '비밀이 아닌 필드는 남아야 디버깅이 된다');
    });

    test('refreshToken · password · secret 도 가린다', () {
      const body = '{"refreshToken":"RT","password":"PW","secret":"S"}';

      final logged = redactBody(body);

      expect(logged, isNot(contains('"RT"')));
      expect(logged, isNot(contains('"PW"')));
      expect(logged, isNot(contains('"S"')));
    });

    test('토큰이 없는 본문은 그대로 남는다', () {
      const body = '{"id":1,"nickname":"보리아빠"}';
      expect(redactBody(body), body);
    });
  });
}

// 로그의 좌표는 소수 둘째 자리까지만 남는다 — 이슈 #186.
//
// 비밀(키·토큰)은 지우고 좌표는 자른다. 통째로 지우면 위치 디버깅이 안 되고(#160 은 좌표를
// 눈으로 보고 잡았다), 그대로 두면 로그를 이슈에 붙이는 순간 어느 집 앞인지가 남는다.
// 둘째 자리는 약 1.1km 격자다 — "강남역 근처" 는 남고 집은 안 남는다.
//
// 값을 잰다. "가려졌다" 만 보면 셋째 자리가 남아도 통과한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/log_redaction.dart';

void main() {
  group('URL 의 좌표', () {
    test('lat·lng 는 소수 둘째 자리까지만 남는다 — 집 앞 좌표가 로그에 남지 않는다', () {
      final url = Uri.https('api.example.test', '/api/places/nearby', {
        'lat': '37.544712',
        'lng': '127.056339',
        'radius': '3000',
      });

      final logged = redactUrl(url);

      expect(logged, isNot(contains('37.544712')));
      expect(logged, isNot(contains('127.056339')));
      expect(logged, contains('lat=37.54'));
      expect(logged, contains('lng=127.06'), reason: '자르는 것이지 버리는 것이 아니다 — 반올림');
      expect(logged, contains('radius=3000'), reason: '좌표가 아닌 값은 그대로다');
    });

    test('이름의 여러 모양을 다 잡는다 — latitude · Longitude · lon', () {
      for (final entry in {'latitude': '37.123456', 'Longitude': '127.987654', 'lon': '127.5555'}.entries) {
        final url = Uri.https('example.com', '/x', {entry.key: entry.value});
        expect(redactUrl(url), isNot(contains(entry.value)), reason: '파라미터 이름: ${entry.key}');
      }
    });

    test('좌표 이름을 달았지만 숫자가 아니면 그대로 둔다', () {
      final url = Uri.https('example.com', '/x', {'lat': 'unknown'});
      expect(redactUrl(url), contains('lat=unknown'));
    });

    test('비밀은 여전히 지워진다 — 좌표 규칙이 비밀 규칙을 밀어내지 않는다', () {
      final url = Uri.https('example.com', '/x', {'token': 'LEAKED', 'lat': '37.544712'});
      final logged = redactUrl(url);
      expect(logged, isNot(contains('LEAKED')));
      expect(logged, contains(redactedMark));
      expect(logged, contains('lat=37.54'));
    });
  });

  group('본문의 좌표', () {
    test('"lat": 37.544712 는 37.54 가 된다 — 음수 경도와 정수도 같이', () {
      const body = '{"id":1,"lat":37.544712,"lng":127.056339,"start":{"latitude": -33.868820, "longitude": 151.209290},"alt":12}';

      final logged = redactBody(body);

      expect(logged, isNot(contains('37.544712')));
      expect(logged, isNot(contains('151.209290')));
      expect(logged, contains('"lat":37.54'));
      expect(logged, contains('"lng":127.06'));
      expect(logged, contains('"latitude":-33.87'));
      expect(logged, contains('"longitude":151.21'));
      expect(logged, contains('"alt":12'), reason: '좌표가 아닌 숫자는 손대지 않는다');
    });

    test('토큰 지우기와 좌표 자르기가 한 본문에서 같이 된다', () {
      const body = '{"token":"eyJhbGciOi","lat":37.544712}';
      final logged = redactBody(body);
      expect(logged, contains('"token":"$redactedMark"'));
      expect(logged, contains('"lat":37.54'));
    });

    test('좌표가 없는 본문은 그대로다', () {
      const body = '{"name":"보리","age":3}';
      expect(redactBody(body), body);
    });
  });

  test('자릿수는 둘이다 — 셋이면 약 110m 격자라 집이 드러난다', () {
    expect(coordinatePrecision, 2);
    expect(truncateCoordinate('37.544712'), '37.54');
  });
}

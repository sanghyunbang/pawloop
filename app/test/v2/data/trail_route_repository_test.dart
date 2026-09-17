import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/trail_route_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 산책로 코스의 선 — `GET /api/places/trails/{courseId}/route` (이슈 #291).
///
/// 목 응답의 키는 계약의 `TrailRoute` 에서 가져왔다 — 앱이 읽는 키로 목을 만들면 앱이
/// 틀린 키를 읽고 있을 때 테스트가 그 버그에 동의한다(#82).
void main() {
  const base = 'https://api.test';

  http.Response ok(String body) => http.Response.bytes(
        utf8.encode(body), 200,
        headers: {'content-type': 'application/json'},
      );

  const contractBody = '{"courseId":"T_ROUTE_1","name":"서울숲 둘레길","lengthM":2600,"pointCount":3,'
      '"points":[[127.0374,37.5445],[127.0379,37.5449],[127.0385,37.5453]]}';

  test('코스 번호만 경로에 싣는다 — 사용자 좌표는 없다', () async {
    Uri? called;
    final repo = TrailRouteRepository(
      client: MockClient((req) async {
        called = req.url;
        return ok(contractBody);
      }),
      baseUrl: base,
    );

    await repo.fetch('T_ROUTE_1');

    expect(called!.path, '/api/places/trails/T_ROUTE_1/route');
    expect(called!.queryParameters, isEmpty, reason: '쿼리에 아무것도 안 실린다 — 위치도 반경도');
  });

  test('계약의 [경도, 위도] 순서를 그대로 든다', () async {
    final repo = TrailRouteRepository(client: MockClient((_) async => ok(contractBody)), baseUrl: base);

    final route = await repo.fetch('T_ROUTE_1');

    expect(route, isNotNull);
    expect(route!.name, '서울숲 둘레길');
    expect(route.lengthM, 2600);
    expect(route.lngLat, hasLength(3));
    expect(route.lngLat.first[0], 127.0374, reason: '경도가 먼저다 — Walk.path 와 같은 순서');
    expect(route.lngLat.first[1], 37.5445);
  });

  test('같은 코스는 한 번만 받는다 — 시트를 열 때마다 부르는 자리다', () async {
    var calls = 0;
    final repo = TrailRouteRepository(
      client: MockClient((_) async {
        calls++;
        return ok(contractBody);
      }),
      baseUrl: base,
    );

    await repo.fetch('T_ROUTE_1');
    await repo.fetch('T_ROUTE_1');

    expect(calls, 1);
  });

  test('404 · 깨진 본문 · 줄 것이 하나도 없으면 null 이다 — 화면이 죽지 않는다', () async {
    expect(await TrailRouteRepository(client: MockClient((_) async => http.Response('', 404)), baseUrl: base)
        .fetch('NOPE'), isNull);
    expect(await TrailRouteRepository(client: MockClient((_) async => ok('not json')), baseUrl: base)
        .fetch('X'), isNull);
    expect(await TrailRouteRepository(
        client: MockClient((_) async => ok('{"courseId":"X","name":"n","lengthM":1,"pointCount":1,"points":[[127.0,37.0]]}')),
        baseUrl: base).fetch('X'), isNull);
  });

  // ─────────────────────── 선이 없는 코스 (#619) ───────────────────────

  const stopsBody = '{"courseId":"lt9766bc9af8","name":"3.1운동길B","lengthM":4200,'
      '"pointCount":0,"points":[],"waypoints":["보신각","보성사 터","탑골공원"]}';

  test('선이 없어도 경유지가 있으면 답을 든다 — 예전에는 여기서 버려 아무 일도 안 났다', () async {
    final repo = TrailRouteRepository(
        client: MockClient((_) async => ok(stopsBody)), baseUrl: base);

    final route = await repo.fetch('lt9766bc9af8');

    expect(route, isNotNull, reason: '선만 보고 버리면 동네 길이 다시 벙어리가 된다');
    expect(route!.hasLine, isFalse);
    expect(route.lngLat, isEmpty);
    expect(route.waypoints, ['보신각', '보성사 터', '탑골공원']);
    expect(route.lengthM, 4200);
  });

  test('선이 있는 코스는 waypoints 가 비어도 그대로 든다', () async {
    final repo = TrailRouteRepository(
        client: MockClient((_) async => ok(contractBody)), baseUrl: base);

    final route = await repo.fetch('T_ROUTE_1');

    expect(route!.hasLine, isTrue);
    expect(route.waypoints, isEmpty, reason: '옛 본문에 이 칸이 없어도 빈 목록이어야 한다');
  });

  test('경유지가 빈 문자열뿐이면 셈에 안 넣는다 — 빈 칸이 시트에 선다', () async {
    final repo = TrailRouteRepository(
        client: MockClient((_) async => ok(
            '{"courseId":"ltX","name":"n","lengthM":1,"pointCount":0,"points":[],'
            '"waypoints":["", "  ", null]}')),
        baseUrl: base);

    expect(await repo.fetch('ltX'), isNull, reason: '줄 것이 없으면 null 이다');
  });

  test('네트워크 예외도 null 이다', () async {
    final repo = TrailRouteRepository(
      client: MockClient((_) async => throw http.ClientException('down')),
      baseUrl: base,
    );
    expect(await repo.fetch('T_ROUTE_1'), isNull);
  });
}

// 동네 목록과 저장 — 이슈 #342.
//
// ## 여기서 재는 가장 중요한 것
//
// **서버로 코드만 나가는가.** 이 기능이 위치기반서비스 신고 전에도 사는 이유가
// "사용자가 고른 이름이고 좌표가 아니다" 하나인데, 요청 본문에 위경도가 한 번이라도 실리면
// 그 문장이 거짓이 된다. 중심 좌표는 지도의 첫 화면에만 쓰는 값이고 기기를 안 떠난다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/data/region_catalog.dart';
import 'package:heat_trip_flutter/v2/domain/neighborhood.dart';

const _base = 'https://api.example.test';

/// 자산과 같은 모양의 작은 표. 진짜 파일(3,516줄)은 위젯 테스트가 읽기엔 크다.
const _sample = '''
{
 "version":"test",
 "source":"통계청 SGIS · CC BY 4.0",
 "sido":[{"c":"11","n":"서울특별시"},{"c":"26","n":"부산광역시"}],
 "sigungu":[
   {"c":"11200","s":"11","n":"성동구"},
   {"c":"11110","s":"11","n":"종로구"},
   {"c":"26110","s":"26","n":"중구"}],
 "dong":[
   {"c":"1120052000","g":"11200","n":"왕십리2동","lat":37.56146,"lng":127.02732},
   {"c":"1120068000","g":"11200","n":"성수1가제1동","lat":37.54554,"lng":127.04425},
   {"c":"1111051500","g":"11110","n":"청운효자동","lat":37.58528,"lng":126.96876},
   {"c":"2611051000","g":"26110","n":"중앙동","lat":35.10175,"lng":129.03528}]
}
''';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => 'RT';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

({NeighborhoodStore store, List<http.Request> sent}) _fixture({int status = 200}) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return http.Response('{"id":1}', status,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
    baseUrl: _base,
    store: _Tokens(),
  );
  return (store: NeighborhoodStore(client: client, baseUrl: _base), sent: sent);
}

final _catalog = RegionCatalog.parse(_sample);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('목록 읽기', () {
    test('시도 · 시군구 · 동이 이어 붙는다', () {
      expect(_catalog.sidos, ['서울특별시', '부산광역시']);
      expect(_catalog.sigungusOf('서울특별시'), ['성동구', '종로구']);
      expect(
        _catalog.dongsOf(sido: '서울특별시', sigungu: '성동구').map((n) => n.dong),
        ['왕십리2동', '성수1가제1동'],
      );
    });

    test('동 하나가 코드 · 이름 · 중심점을 다 든다', () {
      final n = _catalog.byCode('1120052000')!;

      expect(n.sigunguCode, '11200');
      expect(n.sido, '서울특별시');
      expect(n.districtLabel, '성동구');
      expect(n.label, '성동구 왕십리2동');
      expect(n.lat, closeTo(37.56, 0.01));
    });

    test('출처가 목록과 함께 온다 — CC BY 4.0 이 파생물에도 요구한다', () {
      expect(_catalog.attribution, contains('SGIS'));
      expect(_catalog.attribution, contains('CC BY'));
    });
  });

  group('검색', () {
    test('띄어쓰기를 무시하고 찾는다', () {
      expect(_catalog.search('성동구왕십리').single.dong, '왕십리2동');
    });

    test('시작이 맞는 것을 앞에 둔다 — 찾는 사람이 목록을 끝까지 훑지 않게', () {
      final hits = _catalog.search('중');

      expect(hits.first.dong, '중앙동',
          reason: '"중" 으로 시작하는 동이 "종로구" 안의 것보다 앞이다');
    });

    test('빈 질의는 빈 결과 — 3,516개를 다 그리면 안 된다', () {
      expect(_catalog.search('   '), isEmpty);
    });
  });

  group('현재 위치로 찾기', () {
    test('가까운 순으로 후보를 준다 — 기기 안에서 고른다', () {
      // 성수동 근처 좌표.
      final near = _catalog.nearest(37.5455, 127.0443, limit: 2);

      expect(near.first.dong, '성수1가제1동');
      expect(near.length, 2, reason: '고르는 것은 사람이라 후보를 여럿 준다');
    });

    test('부산 좌표면 부산 동이 먼저다', () {
      expect(_catalog.nearest(35.1018, 129.0353, limit: 1).single.dong, '중앙동');
    });
  });

  group('저장 — 서버로 나가는 것', () {
    test('코드만 나간다 · 좌표도 이름도 안 나간다 (#235 A안)', () async {
      final f = _fixture();
      final seongsu = _catalog.byCode('1120068000')!;

      final ok = await f.store.save(seongsu);

      expect(ok, isTrue);
      expect(f.sent, hasLength(1));
      expect(f.sent.single.method, 'PUT');
      expect(f.sent.single.url.path, '/auth/me');

      final body = jsonDecode(f.sent.single.body) as Map<String, dynamic>;
      expect(body.keys, ['neighborhoodCode']);
      expect(body['neighborhoodCode'], '1120068000');
      expect(f.sent.single.body, isNot(contains('37.5')),
          reason: '중심 좌표는 지도의 첫 화면에만 쓰는 값이고 기기를 안 떠난다');
      expect(f.sent.single.body, isNot(contains('성수')),
          reason: '이름은 서버가 자기 표에서 붙인다 — 받으면 거짓 동네를 띄울 수 있다');
    });

    test('기기에 남아 다시 읽힌다', () async {
      final f = _fixture();
      final seongsu = _catalog.byCode('1120068000')!;

      await f.store.save(seongsu);

      final read = await f.store.read();
      expect(read, seongsu);
      expect(read!.lat, closeTo(37.545, 0.01),
          reason: '지도의 첫 화면이 이 값을 쓴다 — 서버에서 받아 오지 않는다');
    });

    test('서버가 실패해도 기기의 값은 남는다 — 게스트도 지도가 그 동네로 열린다', () async {
      final f = _fixture(status: 401);

      final ok = await f.store.save(_catalog.byCode('1120052000')!);

      expect(ok, isFalse, reason: '서버까지 갔는지를 그대로 돌려준다');
      expect(await f.store.read(), isNotNull);
    });

    test('지우면 서버에도 빈 문자열이 간다', () async {
      final f = _fixture();
      await f.store.save(_catalog.byCode('1120052000')!);

      await f.store.clear();

      expect(await f.store.read(), isNull);
      expect(jsonDecode(f.sent.last.body)['neighborhoodCode'], '');
    });

    test('깨진 값이 저장돼 있어도 null 로 읽는다 — 지도가 죽지 않는다', () async {
      SharedPreferences.setMockInitialValues({'v2.neighborhood': '{"code":"짧음"}'});

      expect(await _fixture().store.read(), isNull);
    });
  });

  group('저장 형식', () {
    test('적은 대로 읽힌다', () {
      final n = _catalog.byCode('1120052000')!;

      expect(Neighborhood.tryParse(jsonDecode(jsonEncode(n.toJson()))), n);
    });

    test('열 자리가 아닌 코드는 null', () {
      expect(Neighborhood.tryParse({'code': '112005', 'lat': 1.0, 'lng': 2.0}), isNull);
    });
  });
}

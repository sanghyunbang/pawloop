import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 주변 장소를 우리 백엔드에서 받아 온다 — 이슈 #40 완료 조건 2 · 4.
///
/// ## 응답을 계약에서 만든다
///
/// 목 응답의 키는 서버의 `PlaceDto`(계약의 `Place`)에서 그대로 가져왔다. 앱이 읽는 키를
/// 보고 목을 만들면 **앱이 틀린 키를 읽고 있을 때 테스트가 그 버그에 동의한다** — #82 에서
/// 실제로 겪었다(`messages` vs `items`).
///
/// ## 서비스키가 없어도 동작해야 한다
///
/// 완료 조건 4 다. 예전 코드는 `Env.tourServiceKey` 가 비면 빈 목록을 돌려줬고, 그 줄이
/// 남아 있으면 키 없는 빌드에서 **지도가 영구히 빈 화면**이 된다.
const String _base = 'https://api.test';

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

PetPlacesRepository _repo(MockClient inner) =>
    PetPlacesRepository(client: inner, baseUrl: _base);

void main() {
  // 이 파일의 단언들은 **서버 전송이 켜진 빌드**를 잰다 — 좌표 순서·키 이름·charset 같은
  // 것들은 정책과 무관한 계약이고, 정책이 꺼져 있으면 요청 자체가 안 나가서 잴 수 없다.
  // 꺼진 쪽은 location_upload_policy_test.dart 가 잰다. (#235)
  setUp(() => LocationUploadPolicy.setForTest(true));
  tearDown(LocationUploadPolicy.resetForTest);

  test('우리 백엔드를 부른다 — 관광공사가 아니다', () async {
    Uri? called;
    final repo = _repo(MockClient((req) async {
      called = req.url;
      return _json('[]', 200);
    }));

    await repo.fetchNearby(lat: 37.5665, lng: 126.9780);

    expect(called!.host, 'api.test');
    expect(called!.path, '/api/places/nearby');
    expect(
      called.toString(),
      isNot(contains('serviceKey')),
      reason: '앱에 그 키가 없다. 있으면 strings 한 번이면 나온다',
    );
  });

  test('계약의 키를 읽는다 — KTO 의 contentid/mapx 가 아니다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"contentId":"2733967","title":"서울숲","source":"kto","category":"12",'
          '"contentTypeId":"12","lat":37.5445,"lng":127.0374,'
          '"addr":"서울특별시 성동구 뚝섬로 273","tel":"02-460-2905",'
          '"image":"https://cdn.example/1.jpg","distM":320.5}]',
          200,
        )));

    final places = await repo.fetchNearby(lat: 37.5665, lng: 126.9780);

    expect(places, hasLength(1));
    final place = places.single;
    expect(place.contentId, '2733967');
    expect(place.title, '서울숲');
    expect(place.contentTypeId, '12');
    expect(place.addr, '서울특별시 성동구 뚝섬로 273');
    expect(place.image, 'https://cdn.example/1.jpg');
    expect(place.lat, 37.5445);
    expect(place.lng, 127.0374);
    expect(place.distM, 320.5);
  });

  test('산책로의 코스 길이를 숫자로 읽는다 — 문장은 셈에 못 쓴다 (#539)', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"contentId":"trail:T_ROUTE_1","title":"서울숲 둘레길","source":"trail",'
          '"category":"trail","lat":37.5445,"lng":127.0374,"addr":"서울 성동구",'
          '"summary":"4.2km · 약 1시간 · 보통","courseM":4200},'
          '{"contentId":"2733967","title":"서울숲","source":"kto","category":"12",'
          '"contentTypeId":"12","lat":37.5445,"lng":127.0374,"addr":""}]',
          200,
        )));

    final places = await repo.fetchNearby(lat: 37.5665, lng: 126.9780);

    expect(places.first.courseM, 4200);
    expect(places.first.summary, '4.2km · 약 1시간 · 보통',
        reason: '문장은 그대로다 — 지도 시트가 그것을 그린다');
    expect(places.last.courseM, isNull,
        reason: '공원은 코스가 아니라 길이가 없다. 0 으로 눕히면 "길이가 0인 코스" 가 된다');
  });

  test('요청 파라미터가 계약과 같다', () async {
    Uri? called;
    final repo = _repo(MockClient((req) async {
      called = req.url;
      return _json('[]', 200);
    }));

    await repo.fetchNearby(
        lat: 37.5, lng: 127.0, radius: 3000, numOfRows: 20, contentTypeId: '39');

    expect(called!.queryParameters, {
      'lat': '37.5',
      'lng': '127.0',
      'radius': '3000',
      'limit': '20',
      'category': '39',
    });
  });

  test('카테고리를 안 주면 파라미터도 안 보낸다 — 서버가 전체를 준다', () async {
    Uri? called;
    final repo = _repo(MockClient((req) async {
      called = req.url;
      return _json('[]', 200);
    }));

    await repo.fetchNearby(lat: 37.5, lng: 127.0);

    expect(called!.queryParameters.containsKey('category'), isFalse);
  });

  test('한글이 깨지지 않는다 — charset 없는 응답을 흉내 내면 여기가 먼저 걸린다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"contentId":"1","title":"반려동물 동반 카페","source":"kto",'
          '"contentTypeId":"39","lat":37.5,"lng":127.0,"addr":"서울 강남구","distM":10}]',
          200,
        )));

    final places = await repo.fetchNearby(lat: 37.5, lng: 127.0);

    expect(places.single.title, '반려동물 동반 카페');
    expect(places.single.addr, '서울 강남구');
  });

  test('좌표가 0 인 장소는 뺀다 — 지도에 0,0 마커를 찍으면 안 된다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"contentId":"1","title":"좌표 없음","lat":0,"lng":0},'
          '{"contentId":"2","title":"정상","lat":37.5,"lng":127.0}]',
          200,
        )));

    final places = await repo.fetchNearby(lat: 37.5, lng: 127.0);

    expect(places.map((p) => p.contentId), ['2']);
  });

  test('category 가 생략된 응답도 읽는다 — 서버가 모르는 콘텐츠타입이면 뺀다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"contentId":"1","title":"기타","contentTypeId":"99",'
          '"lat":37.5,"lng":127.0,"addr":"어딘가"}]',
          200,
        )));

    final places = await repo.fetchNearby(lat: 37.5, lng: 127.0);

    expect(places.single.contentTypeId, '99',
        reason: '원래 값은 contentTypeId 에 그대로 있고, 앱이 그것으로 기타 폴백을 한다');
  });

  // ───────────── 실패를 빈 목록으로 뭉치지 않는다 (#515) ─────────────
  //
  // 예전에는 이 셋이 전부 `const []` 였고, 화면은 그것을 받아 **"이 지역엔 등록된 곳이
  // 없어요"** 를 그렸다 — 서버가 죽은 날 하는 거짓말이다. `pet.dart` 가 커뮤니티 더미 앞에
  // 같은 문장을 적어 뒀다: "화면이 서버를 못 불렀을 때 그릴 것은 빈 목록이 아니라
  // '불러오지 못했어요' 다."

  test('서버가 거절하면 이유와 함께 던진다 — 429 는 429 라고 말한다', () async {
    const probes = <(int, PlaceFailureKind)>[
      (400, PlaceFailureKind.unavailable),
      (429, PlaceFailureKind.rateLimited),
      (500, PlaceFailureKind.unavailable),
    ];
    for (final (status, kind) in probes) {
      final repo = _repo(MockClient((req) async => _json('{}', status)));

      await expectLater(
        repo.fetchNearby(lat: 37.5, lng: 127.0),
        throwsA(isA<PlaceFailure>().having((e) => e.kind, 'kind', kind)),
        reason: '상태 $status',
      );
    }
  });

  test('연결이 끊기면 network 라고 말한다 — 다시 시도하면 되는 실패다', () async {
    final repo = _repo(MockClient((req) async => throw const _Boom()));

    await expectLater(
      repo.fetchNearby(lat: 37.5, lng: 127.0),
      throwsA(isA<PlaceFailure>().having((e) => e.kind, 'kind', PlaceFailureKind.network)),
    );
  });

  test('200 인데 배열이 아니면 계약 위반이다 — 빈 목록으로 삼키면 아무도 못 본다', () async {
    final repo = _repo(MockClient((req) async => _json('{"items":[]}', 200)));

    await expectLater(
      repo.fetchNearby(lat: 37.5, lng: 127.0),
      throwsA(isA<PlaceFailure>().having((e) => e.kind, 'kind', PlaceFailureKind.unavailable)),
    );
  });

  test('실패마다 화면에 그릴 문구가 있다 — 비어 있으면 화면이 할 말이 없다', () {
    for (final kind in PlaceFailureKind.values) {
      expect(PlaceFailure(kind).message, isNotEmpty, reason: '$kind');
    }
  });
}

class _Boom implements Exception {
  const _Boom();
}

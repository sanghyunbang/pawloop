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

  test('실패는 빈 목록이다 — 예전 동작 그대로라 화면이 안 깨진다', () async {
    for (final status in const [400, 429, 500]) {
      final repo = _repo(MockClient((req) async => _json('{}', status)));

      expect(await repo.fetchNearby(lat: 37.5, lng: 127.0), isEmpty,
          reason: '상태 $status');
    }
  });

  test('연결이 끊겨도 던지지 않는다', () async {
    final repo = _repo(MockClient((req) async => throw const _Boom()));

    expect(await repo.fetchNearby(lat: 37.5, lng: 127.0), isEmpty);
  });
}

class _Boom implements Exception {
  const _Boom();
}

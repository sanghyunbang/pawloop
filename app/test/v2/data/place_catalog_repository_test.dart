import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/place_catalog_repository.dart';

/// 전국 한 벌을 기기에 두는 길 — 이슈 #273 (#235 A4).
///
/// ## 여기서 재는 것
///
/// 이 경로의 존재 이유는 **요청에 좌표가 없다**는 것이다. 그것이 성립하려면 나머지가
/// 전부 맞아야 한다 — 한 벌을 받아 파일에 남기는가, `ETag` 로 304 를 받는가, 빈 답이
/// 갖고 있던 것을 지우지 않는가, 거리를 기기에서 서버와 같은 식으로 재는가.
void main() {
  late Directory tempDir;

  /// 서울 시청 근처 셋 + 강원 하나. 마지막 것이 반경 밖이다.
  const seoulLat = 37.5665;
  const seoulLng = 126.9780;

  List<Map<String, Object?>> catalogJson() => [
        {
          'contentId': '111',
          'title': '서울숲',
          'source': 'kto',
          'contentTypeId': '12',
          'lat': 37.5445,
          'lng': 127.0374,
          'addr': '서울 성동구',
        },
        {
          'contentId': '222',
          'title': '남산',
          'source': 'kto',
          'contentTypeId': '39',
          'lat': 37.5512,
          'lng': 126.9882,
          'addr': '서울 중구',
        },
        {
          'contentId': '333',
          'title': '먼 곳',
          'source': 'kto',
          'contentTypeId': '12',
          'lat': 38.5000,
          'lng': 127.0000,
          'addr': '강원',
        },
      ];

  /// 요청을 기록하는 가짜 서버.
  ({List<http.Request> requests, MockClient client}) fakeServer({
    String etag = '"abc123"',
    List<Map<String, Object?>>? body,
    int status = 200,
  }) {
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req);
      if (status == 304) {
        return http.Response('', 304, headers: {'etag': etag});
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(body ?? catalogJson())),
        status,
        headers: {'etag': etag, 'content-type': 'application/json'},
      );
    });
    return (requests: requests, client: client);
  }

  /// 뒤에서 도는 갱신이 끝나기를 기다린다.
  ///
  /// [PlaceCatalogRepository.all] 은 갖고 있는 것을 **먼저 주고** 갱신은 뒤로 돌린다.
  /// 그래야 화면이 안 멈추기 때문이다. 그래서 테스트가 요청을 세려면 이벤트 루프를
  /// 몇 바퀴 돌려 줘야 한다 — 고정된 delay 를 쓰면 느린 CI 에서 깜빡인다.
  Future<void> settle(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  PlaceCatalogRepository repo(http.Client client) => PlaceCatalogRepository(
        client: client,
        baseUrl: 'https://example.test',
        cacheDirectory: () async => tempDir,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('place_catalog_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    LocationUploadPolicy.resetForTest();
    // 뒷단 갱신이 파일을 쓰는 중일 수 있다. 윈도우는 그때 지우기가 실패한다
    // (errno 145) — 임시 디렉터리 청소가 테스트를 빨갛게 만들 이유는 없다.
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('요청에 좌표가 없다', () {
    test('경로에 쿼리스트링이 아예 없다 — 이 설계 전체가 그것이다', () async {
      final server = fakeServer();

      await repo(server.client).all();

      expect(server.requests, hasLength(1));
      final uri = server.requests.single.url;
      expect(uri.path, '/api/places/catalog');
      expect(
        uri.queryParameters,
        isEmpty,
        reason: '좌표든 지역이든 쿼리에 실리는 순간 「보낸 것이 없다」 가 거짓이 된다',
      );
    });

    test('본문도 없다 — GET 이다', () async {
      final server = fakeServer();

      await repo(server.client).all();

      expect(server.requests.single.method, 'GET');
      expect(server.requests.single.body, isEmpty);
    });
  });

  group('ETag', () {
    test('받은 ETag 를 다음 요청의 If-None-Match 에 싣는다', () async {
      final server = fakeServer(etag: '"deadbeef"');
      final subject = repo(server.client);

      await subject.all();
      // 하루가 지난 것으로 만든다.
      SharedPreferences.setMockInitialValues({
        'place_catalog_etag_v1': '"deadbeef"',
        'place_catalog_checked_at_v1': 0,
      });
      await subject.all();
      await settle(() => server.requests.length >= 2);

      expect(server.requests, hasLength(2));
      expect(
        server.requests.last.headers['If-None-Match'],
        '"deadbeef"',
        reason: '이 헤더가 없으면 하루마다 2.83MB 를 통째로 다시 받는다',
      );
    });

    test('갖고 있는 것이 없으면 ETag 를 안 댄다 — 대면 304 에 본문이 없어 영원히 빈 채로 남는다', () async {
      // 파일 캐시는 지워졌는데(OS 청소·「캐시 삭제」) SharedPreferences 의 ETag 는 남은 상태.
      SharedPreferences.setMockInitialValues({
        'place_catalog_etag_v1': '"abc123"',
        'place_catalog_checked_at_v1': DateTime.now().millisecondsSinceEpoch,
      });
      final server = fakeServer();

      final places = await repo(server.client).all();

      expect(server.requests, hasLength(1));
      expect(
        server.requests.single.headers.containsKey('If-None-Match'),
        isFalse,
        reason: '''
메모리가 비었는데 ETag 를 대면 서버가 304 를 주고, 304 에는 본문이 없어 채울 것이 없다.
"다시 시도" 를 눌러도 또 304 라 서버 내용이 바뀔 때까지 사용자가 할 수 있는 일이 없다 —
#283 검토가 실측으로 잡았다.''',
      );
      expect(places, hasLength(3), reason: 'ETag 없이 물었으니 200 에 본문이 와야 한다');
    });

    test('304 를 받으면 갖고 있던 것을 그대로 쓴다', () async {
      final first = fakeServer();
      final subject = repo(first.client);
      final before = await subject.all();
      expect(before, hasLength(3));

      SharedPreferences.setMockInitialValues({
        'place_catalog_etag_v1': '"abc123"',
        'place_catalog_checked_at_v1': 0,
      });
      final notModified = fakeServer(status: 304);
      final reopened = repo(notModified.client);

      // **첫 답만 보면 안 된다.** 파일 캐시가 이미 답을 갖고 있어서, 304 를 「빈 목록」
      // 으로 잘못 읽어도 첫 호출은 초록불이다(실측 — 그 버그를 심어도 안 걸렸다).
      // 갱신이 끝난 **뒤에** 다시 물어야 304 처리를 실제로 잰다.
      await reopened.all();
      await settle(() => notModified.requests.isNotEmpty);

      expect(
        await reopened.all(),
        hasLength(3),
        reason: '304 는 본문이 없다. 그것을 「빈 목록」 으로 읽으면 지도가 사라진다',
      );
    });
  });

  group('캐시', () {
    test('파일에 남아서, 새 인스턴스가 네트워크 없이 읽는다', () async {
      final first = fakeServer();
      await repo(first.client).all();

      final second = fakeServer();
      final places = await repo(second.client).all();

      expect(places, hasLength(3));
      expect(
        second.requests,
        isEmpty,
        reason: '''
앱을 켤 때마다 2.83MB 를 받으면 이 설계의 값이 사라진다. 서버 캐시가 24시간이라
그보다 자주 물을 이유도 없다.''',
      );
    });

    test('24시간이 지나면 다시 확인한다', () async {
      final first = fakeServer();
      await repo(first.client).all();

      SharedPreferences.setMockInitialValues({
        'place_catalog_etag_v1': '"abc123"',
        'place_catalog_checked_at_v1':
            DateTime.now().millisecondsSinceEpoch -
                PlaceCatalogRepository.refreshInterval.inMilliseconds -
                1000,
      });

      final second = fakeServer();
      final subject = repo(second.client);
      await subject.all();
      await settle(() => second.requests.isNotEmpty);

      expect(second.requests, isNotEmpty, reason: '영영 안 물으면 새 장소가 안 보인다');
    });
  });

  group('실패', () {
    test('빈 배열이 와도 갖고 있던 한 벌을 안 지운다', () async {
      final first = fakeServer();
      await repo(first.client).all();

      SharedPreferences.setMockInitialValues({
        'place_catalog_etag_v1': '"abc123"',
        'place_catalog_checked_at_v1': 0,
      });
      final empty = fakeServer(body: const [], etag: '"empty"');
      final subject = repo(empty.client);
      await subject.all();
      await settle(() => empty.requests.isNotEmpty);

      expect(
        await subject.all(),
        hasLength(3),
        reason: '''
서버는 예산 소진·상류 실패를 200 + [] 로 준다(계약). 그것을 저장하면 갖고 있던 한 벌을
지우고 지도가 비는데, 서버가 회복해도 다음 갱신까지 빈 채로 남는다.''',
      );
    });

    test('서버가 죽어도 던지지 않는다 — 빈 목록이다', () async {
      final server = fakeServer(status: 500);

      expect(await repo(server.client).all(), isEmpty);
    });

    test('네트워크가 끊겨도 던지지 않는다', () async {
      final client = MockClient((_) async => throw const SocketException('끊김'));

      expect(await repo(client).all(), isEmpty);
    });

    test('hasCatalog 가 「못 받음」 과 「없음」 을 가른다 — 둘 다 nearby 는 빈 목록이다', () async {
      final dead = MockClient((_) async => throw const SocketException('끊김'));
      final subject = repo(dead);

      expect(subject.hasCatalog, isFalse, reason: '아직 아무것도 안 받았다');
      await subject.all();
      expect(
        subject.hasCatalog,
        isFalse,
        reason: '''
실패했는데 true 면 지도 화면이 "이 지역엔 등록된 곳이 없어요, 지도를 움직여 보세요" 라고
말한다 — 네트워크가 끊긴 사람에게 시킨 대로 해도 소용없는 안내다.''',
      );

      final alive = fakeServer();
      final second = repo(alive.client);
      await second.all();
      expect(second.hasCatalog, isTrue);
    });

    test('retry() 는 백오프를 건너뛴다 — 버튼을 눌렀는데 5분을 기다리라고 하면 버튼이 거짓말이다',
        () async {
      var calls = 0;
      var failing = true;
      final client = MockClient((_) async {
        calls++;
        if (failing) throw const SocketException('끊김');
        return http.Response.bytes(utf8.encode(jsonEncode(catalogJson())), 200,
            headers: {'etag': '"abc"', 'content-type': 'application/json'});
      });
      final subject = repo(client);

      await subject.all();
      await subject.all();
      expect(calls, 1, reason: '전제 — 자동 재호출은 백오프에 막힌다');

      failing = false;
      await subject.retry();

      expect(calls, 2, reason: '사람이 누른 재시도는 막히면 안 된다');
      expect(subject.hasCatalog, isTrue);
      expect(await subject.all(), hasLength(3));
    });

    test('실패한 뒤에는 곧바로 다시 부르지 않는다 — 산책 중 5m 마다 재시도가 돈다', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        throw const SocketException('끊김');
      });
      final subject = repo(client);

      await subject.all();
      await subject.all();
      await subject.all();

      expect(
        calls,
        1,
        reason: '''
walk_tracking_screen 은 위치가 5m 움직일 때마다 `if (!_poisLoaded)` 를 보고 다시 부른다.
한 벌을 못 받으면 _poisLoaded 가 안 서므로 그 조건이 계속 참이고, 백오프가 없으면
산책 내내 요청이 쏟아진다. 서버의 failure-backoff-minutes 가 같은 것을 막는다.''',
      );
    });
  });

  group('기기에서 거르기', () {
    test('반경 밖은 빠지고 거리순으로 온다', () async {
      final server = fakeServer();

      final places = await repo(server.client)
          .nearby(lat: seoulLat, lng: seoulLng, radius: 8000);

      expect(places.map((p) => p.contentId), ['222', '111']);
      expect(
        places.first.distM,
        lessThan(places.last.distM),
        reason: '거리순이 아니면 지도 아래 목록이 엉뚱한 순서로 뜬다',
      );
    });

    test('카테고리로 거른다', () async {
      final server = fakeServer();

      final places = await repo(server.client).nearby(
          lat: seoulLat, lng: seoulLng, radius: 8000, contentTypeId: '12');

      expect(places.map((p) => p.contentId), ['111']);
    });

    test('limit 만큼 자른다', () async {
      final server = fakeServer();

      final places = await repo(server.client)
          .nearby(lat: seoulLat, lng: seoulLng, radius: 100000, limit: 2);

      expect(places, hasLength(2));
    });

    test('거리가 서버와 같은 식이다 — 하버사인', () {
      // 서울시청 → 서울숲. 지도상 약 4.5km 다.
      final meters = haversineMeters(seoulLat, seoulLng, 37.5445, 127.0374);

      expect(meters, closeTo(5400, 400));
      expect(
        haversineMeters(37.5, 127.0, 37.5, 127.0),
        0,
        reason: '같은 점의 거리는 0 이다',
      );
    });

    test('거리가 응답이 아니라 기기에서 온다 — 서버는 distM 을 안 싣는다', () async {
      // 카탈로그 JSON 에 distM 이 아예 없다(위 catalogJson 참조).
      final server = fakeServer();

      final places = await repo(server.client)
          .nearby(lat: seoulLat, lng: seoulLng, radius: 8000);

      expect(
        places.every((p) => p.distM > 0),
        isTrue,
        reason: '''
서버가 이 값을 계산할 좌표를 갖고 있지 않다. 응답에서 읽으려 들면 전부 0 이 되고
목록의 거리 라벨이 통째로 사라진다.''',
      );
    });
  });

  group('정책과의 연결', () {
    test('A안 빌드에서 fetchNearby 가 카탈로그로 간다 — 좌표가 안 나간다', () async {
      LocationUploadPolicy.setForTest(false);

      final calls = <Uri>[];
      final client = MockClient((req) async {
        calls.add(req.url);
        return http.Response.bytes(
            utf8.encode(jsonEncode(catalogJson())), 200,
            headers: {'etag': '"abc"', 'content-type': 'application/json'});
      });

      // **`fetchNearby` 를 실제로 지나간다.** 카탈로그를 직접 부르면 라우팅이 끊겨도
      // 초록불이라, 그 검사는 이름이 말하는 것을 안 재는 것이 된다.
      final places = await PetPlacesRepository(
        client: MockClient((req) async {
          calls.add(req.url);
          return http.Response('[]', 200);
        }),
        baseUrl: 'https://example.test',
        catalog: PlaceCatalogRepository(
          client: client,
          baseUrl: 'https://example.test',
          cacheDirectory: () async => tempDir,
        ),
      ).fetchNearby(lat: seoulLat, lng: seoulLng, radius: 8000);

      expect(places, isNotEmpty, reason: 'A안 빌드에서 지도가 비면 안 된다 — 그것이 이 이슈다');
      expect(calls.single.queryParameters, isEmpty);
      expect(
        calls.single.path,
        '/api/places/catalog',
        reason: 'nearby 로 갔다면 좌표가 쿼리에 실려 나간 것이다',
      );
    });

    test('B안 빌드에서는 예전 경로 그대로다 — 좌표를 실어 nearby 를 부른다', () async {
      LocationUploadPolicy.setForTest(true);

      final calls = <Uri>[];
      final client = MockClient((req) async {
        calls.add(req.url);
        return http.Response.bytes(utf8.encode('[]'), 200);
      });

      await PetPlacesRepository(client: client, baseUrl: 'https://example.test')
          .fetchNearby(lat: seoulLat, lng: seoulLng);

      expect(calls.single.path, '/api/places/nearby');
      expect(
        calls.single.queryParameters['lat'],
        '$seoulLat',
        reason: '''
신고를 마친 뒤 켜는 길이다(#200). 이 검사가 없으면 카탈로그를 붙이면서 그 길을
조용히 끊어 놓고도 모른다.''',
      );
    });
  });
}

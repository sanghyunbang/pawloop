// 산책의 장소 축 — 보내는 모양 · 받는 모양 · 초안에 실려 남는가 (#338).
//
// 목의 키는 서버의 `WalkResponse`(계약의 `Walk`)와 `WalkStatsResponse` 에서 그대로 가져왔다.
// 앱이 읽는 키를 보고 목을 만들면, 앱이 틀린 키를 읽고 있을 때 테스트가 그 버그에 동의한다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

({WalkRepository repo, List<http.Request> seen}) _repo(
  http.Response Function(http.Request request) answer,
) {
  final seen = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      return answer(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: WalkRepository(baseUrl: _base, client: client), seen: seen);
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _walkJson({Object? place}) => {
      'id': 7,
      'dogId': 3,
      'clientWalkId': 'abc12345',
      'startedAt': '2026-09-01T00:30:00Z',
      'endedAt': '2026-09-01T01:00:00Z',
      'distanceM': 2400,
      'durationS': 1800,
      'path': null,
      'memo': null,
      'weather': null,
      'place': place,
    };

void main() {
  group('보내는 모양', () {
    test('카탈로그에서 고른 곳은 이름·출처·식별자 셋을 보낸다', () async {
      final r = _repo((_) => _json(_walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1, 0, 30),
        distanceM: 2400,
        durationS: 1800,
        place: const WalkPlaceRef(title: '서울숲', source: 'kto', contentId: '2733967'),
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body['placeName'], '서울숲');
      expect(body['placeSource'], 'kto');
      expect(body['placeContentId'], '2733967');
    });

    test('손으로 적은 이름은 이름만 보낸다 — 반쪽짜리 참조는 서버가 400 이다', () async {
      final r = _repo((_) => _json(_walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1, 0, 30),
        distanceM: 2400,
        durationS: 1800,
        place: const WalkPlaceRef(title: '우리 아파트 뒷길'),
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body['placeName'], '우리 아파트 뒷길');
      expect(body.containsKey('placeSource'), isFalse);
      expect(body.containsKey('placeContentId'), isFalse);
    });

    test('장소가 없으면 키 자체를 안 보낸다', () async {
      final r = _repo((_) => _json(_walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1, 0, 30),
        distanceM: 2400,
        durationS: 1800,
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body.containsKey('placeName'), isFalse);
    });
  });

  group('받는 모양', () {
    test('응답의 place 를 읽는다 · 없으면 null 이다', () async {
      final r = _repo((_) => _json(_walkJson(
            place: {'source': 'trail', 'contentId': 'trail:41', 'title': 'DMZ 평화의 길'},
          ), status: 201));

      final saved = await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1, 0, 30),
        distanceM: 2400,
        durationS: 1800,
      );

      expect(saved.place?.title, 'DMZ 평화의 길');
      expect(saved.place?.isCatalog, isTrue);
      expect(ServerWalk.tryParse(_walkJson())?.place, isNull);
    });

    test('통계의 topPlaces 를 읽는다 — 모양이 깨진 항목은 버리고 나머지를 살린다', () async {
      final r = _repo((_) => _json({
            'weekStart': '2026-09-07',
            'weekEnd': '2026-09-13',
            'weekKm': [1.0, 0, 0, 0, 0, 0, 0],
            'totalKm': 1.0,
            'walkCount': 1,
            'avgKm': 1.0,
            'allTimeKm': 5.0,
            'allTimeCount': 4,
            'allTimeMinutes': 120,
            'topPlaces': [
              {'place': {'source': 'kto', 'contentId': '2733967', 'title': '서울숲'}, 'count': 3},
              {'place': {'source': 'kto', 'contentId': 'x'}, 'count': 2},
              {'count': 1},
            ],
          }));

      final stats = await r.repo.stats();

      expect(stats.topPlaces, hasLength(1));
      expect(stats.topPlaces.single.place.title, '서울숲');
      expect(stats.topPlaces.single.count, 3);
    });
  });

  group('초안이 장소를 들고 다닌다', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('저장했다 읽어도 장소가 그대로다 — 비행기 모드에서 며칠 뒤 올라가도 잃지 않는다', () async {
      final outbox = await WalkOutbox.open();
      final draft = WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 7, 13),
        endedAt: DateTime(2026, 9, 7, 13, 30),
        distanceM: 1200,
        durationS: 1800,
        path: const [],
        place: const WalkPlaceRef(title: '서울숲', source: 'kto', contentId: '2733967'),
      );
      await outbox.put(draft);

      final again = await WalkOutbox.open();
      final loaded = again.pending.single;

      expect(loaded.place?.title, '서울숲');
      expect(loaded.place?.source, 'kto');
      expect(loaded.place?.contentId, '2733967');
    });

    test('dropPlace 는 장소를 없앤다 — 이름 칸을 비우고 저장한 경우다', () {
      final draft = WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 7, 13),
        endedAt: DateTime(2026, 9, 7, 13, 30),
        distanceM: 1200,
        durationS: 1800,
        path: const [],
        place: const WalkPlaceRef(title: '서울숲', source: 'kto', contentId: '2733967'),
      );

      expect(draft.copyWith(memo: '메모만').place?.title, '서울숲');
      expect(draft.copyWith(dropPlace: true).place, isNull);
    });
  });
}

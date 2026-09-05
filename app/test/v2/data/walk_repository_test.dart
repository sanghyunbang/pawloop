// WalkRepository — 요청 모양과 **실패의 종류** 를 잠근다 (이슈 #145).
//
// 실제 네트워크를 타지 않는다. `AuthedClient` 에 `MockClient` 를 꽂아 요청을 가로챈다 —
// `family_repository_test.dart` 가 쓰는 방식 그대로다(이 저장소에는 mockito 가 없다).
//
// ## 응답 목을 계약에서 만든다
//
// 목의 키는 서버의 `WalkResponse`(계약의 `Walk`)에서 그대로 가져왔다. **앱이 읽는 키를
// 보고 목을 만들면 앱이 틀린 키를 읽고 있을 때 테스트가 그 버그에 동의한다** — #82 에서
// 실제로 겪었다(`messages` vs `items`).
//
// ## 여기서 재는 것
//
//  1. 좌표를 **[경도, 위도]** 로 보내는가. 이 한 줄이 M1 의 가장 흔한 버그다(#24).
//  2. 시각에 오프셋이 붙는가. 빠지면 서버가 400 을 준다.
//  3. 상태 코드가 **다시 보내도 되는 실패**와 **그러면 안 되는 실패**로 갈리는가.
//     이 구분이 틀리면 전송 대기 큐가 영구 거절 요청을 영원히 재시도한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  String? access = 'access-token';
  String? refresh = 'refresh-token';

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

({WalkRepository repo, List<http.Request> seen}) repositoryThatAnswers(
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

/// 계약의 `Walk` 그대로. 앱이 읽는 키가 아니라 **서버가 주는 키**다.
Map<String, Object?> walkJson({
  int id = 7,
  int dogId = 3,
  Object? path,
  String? memo = '한강 한 바퀴',
}) =>
    {
      'id': id,
      'dogId': dogId,
      'clientWalkId': 'abc12345',
      'startedAt': '2026-09-01T00:30:00Z',
      'endedAt': '2026-09-01T01:00:00Z',
      'distanceM': 2400,
      'durationS': 1800,
      'path': path,
      'memo': memo,
      'weather': '맑음 24°C',
    };

void main() {
  // 이 파일의 단언들은 **서버 전송이 켜진 빌드**를 잰다 — 좌표 순서·키 이름·charset 같은
  // 것들은 정책과 무관한 계약이고, 정책이 꺼져 있으면 요청 자체가 안 나가서 잴 수 없다.
  // 꺼진 쪽은 location_upload_policy_test.dart 가 잰다. (#235)
  setUp(() => LocationUploadPolicy.setForTest(true));
  tearDown(LocationUploadPolicy.resetForTest);

  group('저장 요청', () {
    test('좌표를 [경도, 위도] 로 보낸다 — 뒤집으면 서버가 400 을 준다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1, 0, 30),
        distanceM: 2400,
        durationS: 1800,
        path: const [
          [126.9780, 37.5665],
          [126.9800, 37.5670],
        ],
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      final path = body['path'] as List;
      expect(
        (path.first as List).first,
        126.9780,
        reason: '첫 값이 경도다. 37.x 가 오면 앱이 NLatLng 를 그대로 실은 것이다',
      );
      expect((path.first as List)[1], 37.5665);
    });

    test('시각에 오프셋이 붙는다 — 없으면 서버가 400 이다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        // 로컬 시각을 준다. 저장소가 UTC 로 옮겨야 한다.
        startedAt: DateTime(2026, 9, 1, 9, 30),
        endedAt: DateTime(2026, 9, 1, 10, 0),
        distanceM: 2400,
        durationS: 1800,
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body['startedAt'], endsWith('Z'));
      expect(body['endedAt'], endsWith('Z'));
    });

    test('점이 2개 미만이면 path 를 아예 안 보낸다 — LINESTRING 은 점 하나로 못 만든다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1),
        distanceM: 100,
        durationS: 100,
        path: const [
          [126.9780, 37.5665],
        ],
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body.containsKey('path'), isFalse);
    });

    test('경로 · 메모 · 날씨가 없으면 키 자체를 안 보낸다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(), status: 201));

      await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1),
        distanceM: 100,
        durationS: 100,
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body.keys, isNot(contains('path')));
      expect(body.keys, isNot(contains('memo')));
      expect(body.keys, isNot(contains('endedAt')));
      expect(body['clientWalkId'], 'abc12345');
    });

    test('재전송(200)과 첫 저장(201)을 같게 다룬다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(), status: 200));

      final walk = await r.repo.saveWalk(
        dogId: 3,
        clientWalkId: 'abc12345',
        startedAt: DateTime.utc(2026, 9, 1),
        distanceM: 2400,
        durationS: 1800,
      );

      expect(walk.id, 7);
    });
  });

  group('응답 읽기', () {
    test('계약의 키를 읽는다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(path: const [
            [126.9780, 37.5665],
            [126.9800, 37.5670],
          ])));

      final walk = await r.repo.walk(7);

      expect(walk.id, 7);
      expect(walk.dogId, 3);
      expect(walk.clientWalkId, 'abc12345');
      expect(walk.distanceM, 2400);
      expect(walk.durationS, 1800);
      expect(walk.km, 2.4);
      expect(walk.minutes, 30);
      expect(walk.path!.first, [126.9780, 37.5665]);
      expect(walk.memo, '한강 한 바퀴');
      expect(walk.weather, '맑음 24°C', reason: 'charset 없는 응답에서도 한글이 안 깨져야 한다');
    });

    test('목록의 path 가 null 이어도 읽는다 — 서버가 일부러 안 싣는다', () async {
      final r = repositoryThatAnswers((_) => _json({
            'items': [walkJson(path: null)],
            'nextCursor': 'eyJ4Ijox',
            'hasMore': true,
          }));

      final page = await r.repo.walks(limit: 1);

      expect(page.items.single.path, isNull);
      expect(page.nextCursor, 'eyJ4Ijox');
      expect(page.hasMore, isTrue);
    });

    test('모양이 깨진 항목 하나가 나머지를 죽이지 않는다', () async {
      final r = repositoryThatAnswers((_) => _json({
            'items': [
              {'id': 'not-a-number'},
              walkJson(id: 9),
            ],
            'hasMore': false,
          }));

      final page = await r.repo.walks();

      expect(page.items.map((w) => w.id), [9]);
    });

    test('통계의 weekKm 이 짧아도 길이 7 로 채운다 — 화면이 [i] 를 돈다', () async {
      final r = repositoryThatAnswers((_) => _json({
            'weekKm': [1.0, 2.0],
            'totalKm': 3.0,
            'walkCount': 2,
            'avgKm': 1.5,
            'allTimeKm': 10.0,
            'allTimeCount': 5,
            'allTimeMinutes': 120,
          }));

      final stats = await r.repo.stats();

      expect(stats.weekKm.length, 7);
      expect(stats.weekKm[2], 0);
      expect(stats.allTimeCount, 5);
      expect(stats.allTimeMinutes, 120);
    });

    test('반려동물의 species 를 읽는다 — 고양이가 개로 보이면 안 된다', () async {
      final r = repositoryThatAnswers((_) => _json([
            {
              'id': 1,
              'name': '나비',
              'species': 'cat',
              'size': 'small',
              'neutered': true,
              'breed': null,
              'ageMonths': null,
            }
          ]));

      final pets = await r.repo.pets();

      expect(pets.single.species, ServerPetSpecies.cat);
      expect(pets.single.ageMonths, isNull,
          reason: 'null 은 "생일을 모른다" 이지 0개월이 아니다');
    });
  });

  group('실패의 종류', () {
    test('다시 보내도 되는 것과 안 되는 것을 가른다', () async {
      const expected = {
        400: WalkFailureKind.rejected,
        401: WalkFailureKind.unauthorized,
        404: WalkFailureKind.notFound,
        409: WalkFailureKind.rejected,
        429: WalkFailureKind.rateLimited,
        500: WalkFailureKind.network,
      };

      for (final entry in expected.entries) {
        final r = repositoryThatAnswers((_) => _json({}, status: entry.key));

        await expectLater(
          r.repo.walk(1),
          throwsA(isA<WalkFailure>().having((f) => f.kind, '${entry.key}', entry.value)),
        );
      }
    });

    test('재시도 가능 여부가 종류에서 나온다 — 화면마다 다시 정하지 않는다', () {
      expect(WalkFailureKind.network.retryable, isTrue);
      expect(WalkFailureKind.unauthorized.retryable, isTrue);
      expect(WalkFailureKind.rateLimited.retryable, isTrue);
      expect(WalkFailureKind.rejected.retryable, isFalse,
          reason: '400 을 재시도하면 큐가 막히고 정상 기록이 밀려난다');
      expect(WalkFailureKind.notFound.retryable, isFalse);
    });

    test('연결이 끊기면 network 다 — 던지되 종류가 있다', () async {
      final r = repositoryThatAnswers((_) => throw const _Boom());

      await expectLater(
        r.repo.walks(),
        throwsA(isA<WalkFailure>()
            .having((f) => f.kind, 'kind', WalkFailureKind.network)),
      );
    });

    test('반려동물 삭제는 DELETE /api/dogs/{id} 이고 본문 없는 204 다 (#156)', () async {
      final r = repositoryThatAnswers((_) => http.Response('', 204));

      await r.repo.deletePet(3);

      expect(r.seen.single.method, 'DELETE');
      expect(r.seen.single.url.path, '/api/dogs/3');
    });

    test('삭제는 본문 없는 204 다', () async {
      final r = repositoryThatAnswers((_) => http.Response('', 204));

      await r.repo.deleteWalk(7);

      expect(r.seen.single.method, 'DELETE');
      expect(r.seen.single.url.path, '/api/walks/7');
    });
  });

  group('회고 글 교체 (#187)', () {
    test('PUT /api/walks/{id}/memo 로 memo 하나만 보낸다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(memo: '고친 글')));

      final walk = await r.repo.rewriteMemo(7, '고친 글');

      expect(r.seen.single.method, 'PUT');
      expect(r.seen.single.url.path, '/api/walks/7/memo');
      expect(jsonDecode(r.seen.single.body), {'memo': '고친 글'},
          reason: '거리·시간을 함께 보내면 회고가 기록 수정으로 번진다');
      expect(walk.memo, '고친 글');
    });

    test('빈 글도 그대로 보낸다 — 지우는 것은 정상 요청이다', () async {
      final r = repositoryThatAnswers((_) => _json(walkJson(memo: null)));

      final walk = await r.repo.rewriteMemo(7, '');

      expect(jsonDecode(r.seen.single.body), {'memo': ''},
          reason: '앱이 미리 걸러 내면 서버에 도달하지 못해 영영 못 지운다');
      expect(walk.memo, isNull, reason: '서버가 눕힌 값을 그대로 받는다');
    });

    test('404 는 다시 보내도 소용없는 실패다', () async {
      final r = repositoryThatAnswers((_) => _json({'error': {}}, status: 404));

      await expectLater(
        r.repo.rewriteMemo(7, '글'),
        throwsA(isA<WalkFailure>().having((e) => e.retryable, 'retryable', isFalse)),
      );
    });
  });

  test('Authorization 을 여기서 만들지 않는다 — AuthedClient 가 붙인다 (#11)', () async {
    final r = repositoryThatAnswers((_) => _json({'items': [], 'hasMore': false}));

    await r.repo.walks();

    expect(r.seen.single.headers['Authorization'], 'Bearer access-token');
  });
}

class _Boom implements Exception {
  const _Boom();
}

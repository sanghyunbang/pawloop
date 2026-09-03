// 좌표가 기기를 떠나는 자리가 정책 하나를 지나는가 — 이슈 #235.
//
// ## 왜 소스를 세는가
//
// 이건 동작으로만 재면 부족하다. "어디에서도 안 보낸다" 는 **없음의** 주장이라, 있는 것을
// 확인하는 방식으로는 증명이 안 된다. `legacy_shell_reachability_test.dart` 가 같은 이유로
// 같은 방식을 쓴다.
//
// 손으로 훑어서 될 일도 아니다 — 실제로 아홉 경로 중 넷을 놓쳤다. 산책 중 5m 마다 반복되는
// 조회, 산책 시작 지점, 큐의 자동 재전송, 그리고 서버 로그. 열 번째가 생기는 날 사람이
// 알아채리라고 기대하면 안 된다.
//
// ## 동작도 함께 잰다
//
// 소스 스캔은 "정책을 부른다" 까지만 본다. 정책이 실제로 값을 죽이는지는 진짜 저장소에
// `MockClient` 를 꽂아서 본다. 둘 다 있어야 한다 — 부르기만 하고 결과를 버리는 코드는
// 스캔을 통과한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';

  @override
  Future<String?> readRefreshToken() async => 'RT-1';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// `app/lib/v2` 아래 모든 `.dart` 를 읽는다.
///
/// **HTTP 를 부르는 파일만 대상이다.** 좌표 키가 있다고 다 전송이 아니다 —
/// `walk_outbox.dart` 는 `'path': path` 를 쓰지만 그건 `shared_preferences` 로
/// **기기 안에** 적는 `toJson()` 이다. 그 초안이 나중에 올라갈 때는
/// `walk_sync` 가 `WalkRepository.saveWalk` 를 지나므로 거기서 정책이 죽인다.
///
/// 이 구분이 없으면 검사가 로컬 저장까지 잡아서, 사람이 예외 목록에 파일 이름을
/// 하나씩 적기 시작한다 — 그러면 진짜 전송이 생겨도 그 목록에 숨는다.
List<({String path, String source})> _v2Sources() {
  final root = Directory('lib/v2');
  expect(root.existsSync(), isTrue,
      reason: '트리를 옮겼다면 이 테스트도 함께 고친다. skip 하지 않는다');

  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (
            path: f.path.replaceAll(r'\', '/'),
            source: f.readAsStringSync(),
          ))
      .toList();
}

/// 이 파일이 실제로 요청을 내보내는가.
bool _sendsHttp(String source) =>
    source.contains('package:http') || source.contains('AuthedClient');

void main() {
  group('소스 — 좌표를 보내는 자리가 정책을 지난다', () {
    test('요청에 lat/lng 를 싣는 파일은 정책 파일 하나뿐이 아니라 정책을 부른다', () {
      final offenders = <String>[];

      for (final f in _v2Sources()) {
        if (f.path.endsWith('location_upload_policy.dart')) continue;
        if (!_sendsHttp(f.source)) continue;

        // 쿼리·본문에 좌표 키를 싣는 모양. 파싱(`j['lat']`)은 들어오는 값이라 제외한다.
        final sends = RegExp(r"""['"]lat['"]\s*:|['"]lng['"]\s*:""").hasMatch(f.source);
        if (!sends) continue;

        if (!f.source.contains('LocationUploadPolicy')) {
          offenders.add(f.path);
        }
      }

      expect(offenders, isEmpty,
          reason: '좌표를 실으면서 정책을 안 지나는 파일이다. 새 전송 경로를 만들었다면 '
              'LocationUploadPolicy 를 지나게 한다 — 아홉 곳에 if 를 흩는 방식은 '
              '열 번째가 생기는 날 아무도 모른다');
    });

    test('산책 경로를 싣는 자리도 정책을 지난다', () {
      final offenders = <String>[];

      for (final f in _v2Sources()) {
        if (f.path.endsWith('location_upload_policy.dart')) continue;
        if (!_sendsHttp(f.source)) continue;
        if (!RegExp(r"""['"]path['"]\s*:|['"]pathT['"]\s*:""").hasMatch(f.source)) {
          continue;
        }
        if (!f.source.contains('LocationUploadPolicy')) offenders.add(f.path);
      }

      expect(offenders, isEmpty,
          reason: 'path·pathT 는 산책 전 구간의 원시 좌표열이다 — 집과 직장을 그대로 그린다');
    });
  });

  group('동작 — 정책이 실제로 값을 죽인다', () {
    test('기본 빌드는 산책 경로를 안 싣는다', () async {
      Map<String, Object?>? sent;
      final repo = WalkRepository(
        baseUrl: _base,
        client: AuthedClient(
          inner: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, Object?>;
            return _json({
              'id': 1,
              'dogId': 1,
              'startedAt': '2026-09-01T00:00:00Z',
              'distanceM': 1200,
              'durationS': 900,
            }, status: 201);
          }),
          baseUrl: _base,
          store: _FakeTokenStore(),
        ),
      );

      await repo.saveWalk(
        dogId: 1,
        clientWalkId: 'w-1',
        startedAt: DateTime.utc(2026, 9, 1),
        distanceM: 1200,
        durationS: 900,
        path: const [
          [126.9780, 37.5665],
          [126.9790, 37.5670],
          [126.9800, 37.5675],
        ],
        pathT: const [0, 30, 60],
      );

      expect(sent, isNotNull);
      expect(sent!.containsKey('path'), isFalse,
          reason: '기본값이 안전한 쪽이다 — --dart-define=UPLOAD_LOCATION=true 로만 켜진다');
      expect(sent!.containsKey('pathT'), isFalse);
      expect(sent!['distanceM'], 1200,
          reason: '거리·시간은 온디바이스 계산이라 그대로 간다. 산책 기록 자체는 살아야 한다');
    });

    test('기본 빌드는 주변 장소를 묻지 않는다 — 요청 자체가 안 나간다', () async {
      var calls = 0;
      final repo = PetPlacesRepository(
        baseUrl: _base,
        client: MockClient((_) async {
          calls++;
          return _json(const []);
        }),
      );

      final places = await repo.fetchNearby(lat: 37.5665, lng: 126.9780);

      expect(calls, 0, reason: '좌표가 쿼리스트링에 실려 나가는 자리다');
      expect(places, isEmpty, reason: '실패와 같은 값이라 부르는 쪽이 이미 다룬다');
    });

    test('기본 빌드는 커뮤니티 글에 장소를 안 싣는다', () async {
      Map<String, Object?>? sent;
      final repo = CommunityRepository(
        baseUrl: _base,
        client: AuthedClient(
          inner: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, Object?>;
            return _json({
              'id': 1,
              'author': {'userId': 7, 'nickname': 'n'},
              'board': 'pet_place',
              'title': 't',
              'body': 'b',
              'commentCount': 0,
              'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
              'createdAt': '2026-09-01T00:00:00Z',
            }, status: 201);
          }),
          baseUrl: _base,
          store: _FakeTokenStore(),
        ),
      );

      await repo.createPost(
        board: CommunityBoard.petPlace,
        title: '성수동 카페',
        body: '동반 가능해요',
        loc: '서울숲',
        contentId: '126508',
      );

      expect(sent, isNotNull);
      expect(sent!.containsKey('loc'), isFalse);
      expect(sent!.containsKey('contentId'), isFalse);
      expect(sent!['title'], '성수동 카페', reason: '글 자체는 그대로 써진다');
    });
  });

    test('큐에 남아 있던 옛 초안도 경로 없이 올라간다 — 사용자 탭이 없는 경로다', () async {
      // 이게 A5 다(#235). 저장에 실패한 초안이 shared_preferences 에 남아 다음 실행에서
      // **사용자 탭 없이** 올라간다. 업데이트로 온디바이스 빌드를 받은 사람의 기기에는
      // 옛 경로가 든 초안이 이미 들어 있다.
      //
      // 큐를 비우는 마이그레이션이 필요하다고 이슈에 적었는데, 확인해 보니 필요 없다 —
      // 큐에서 네트워크로 가는 길이 WalkSync 의 saveWalk 하나뿐이고 거기서 정책이 죽인다.
      // 기존 walk_outbox_test 는 저장소를 가짜로 갈아끼워서 이 자리를 못 잰다.
      SharedPreferences.setMockInitialValues(<String, Object>{
        WalkOutbox.pendingKey: <String>[
          jsonEncode({
            'clientWalkId': 'old-draft-1',
            'startedAt': '2026-09-01T00:00:00.000Z',
            'endedAt': '2026-09-01T00:30:00.000Z',
            'distanceM': 2400,
            'durationS': 1800,
            'path': [
              [126.9780, 37.5665],
              [126.9800, 37.5670],
            ],
            'pathT': [0, 60],
          }),
        ],
      });

      final bodies = <Map<String, Object?>>[];
      final repo = WalkRepository(
        baseUrl: _base,
        client: AuthedClient(
          inner: MockClient((request) async {
            if (request.url.path == '/api/dogs') {
              return _json(const [
                {'id': 1, 'name': '보리', 'species': 'dog', 'size': 'small'},
              ]);
            }
            bodies.add(jsonDecode(request.body) as Map<String, Object?>);
            return _json({
              'id': 1,
              'dogId': 1,
              'startedAt': '2026-09-01T00:00:00Z',
              'distanceM': 2400,
              'durationS': 1800,
            }, status: 201);
          }),
          baseUrl: _base,
          store: _FakeTokenStore(),
        ),
      );

      final sync = WalkSync(repo, await WalkOutbox.open());
      await sync.flush();

      expect(bodies, hasLength(1), reason: '큐가 실제로 비워졌어야 이 단언이 뜻이 있다');
      expect(bodies.single.containsKey('path'), isFalse,
          reason: '기기에 남아 있던 옛 경로가 자동 재전송으로 올라가면 안 된다');
      expect(bodies.single.containsKey('pathT'), isFalse);
      expect(bodies.single['distanceM'], 2400, reason: '기록 자체는 올라간다');
    });

  test('lib/ 안에서 테스트 창구를 부르는 코드가 없다', () {
    // setForTest 는 assert 안에서만 값을 바꾸므로 릴리스에서는 무해하다. 그래도
    // 운영 코드가 그것을 부르기 시작하면 정책이 런타임 토글이 되고, 이 파일이 적어 둔
    // "배포본에는 갈아끼우는 갈래가 없다" 가 거짓이 된다.
    final offenders = _v2Sources()
        .where((f) => !f.path.endsWith('location_upload_policy.dart'))
        // 이름만 보면 AuthState.resetForTest 같은 남의 창구까지 잡는다 — 정책 것만 본다.
        .where((f) =>
            f.source.contains('LocationUploadPolicy.setForTest') ||
            f.source.contains('LocationUploadPolicy.resetForTest'))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty,
        reason: '운영 코드가 정책을 갈아끼우면 컴파일 타임 보장이 사라진다');
  });

  test('정책의 기본값이 꺼짐이다 — 이 테스트가 초록이려면 아무것도 안 켜져 있어야 한다', () {
    expect(LocationUploadPolicy.uploadsLocation, isFalse,
        reason: 'CI 가 --dart-define=UPLOAD_LOCATION=true 로 도는 날 위 단언들이 전부 '
            '거짓이 된다. 그때 이 한 줄이 먼저 빨간불이 되어 이유를 말한다');
  });
}

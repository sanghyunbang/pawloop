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

/// `app/lib` 아래 **전부**를 읽는다 — 이슈 #235.
///
/// ## 왜 `lib/v2` 가 아닌가
///
/// 예전에는 `lib/v2` 만 훑었다. 그런데 레거시 셸이 아직 좌표를 보낸다 —
/// `emotion_map_repository.dart` 가 현위치를 쿼리로 싣고,
/// `foryou_repository_impl.dart` 가 `userLat`·`userLng` 를 본문에 싣는다.
///
/// v2 화면에서 그리로 가는 길은 없다(`legacy_shell_reachability_test.dart` 가 잠근다).
/// **그래도 APK 에는 컴파일돼 들어간다.** 이슈 본문이 그것을 이렇게 적었다 —
/// 사용자는 못 밟지만 「코드에 없다」 는 거짓입니다.
///
/// 그래서 범위를 넓히고, 레거시는 [_exempt] 에 **이유와 함께** 적는다.
///
/// **HTTP 를 부르는 파일만 대상이다.** 좌표 키가 있다고 다 전송이 아니다 —
/// `walk_outbox.dart` 는 `'path': path` 를 쓰지만 그건 `shared_preferences` 로
/// **기기 안에** 적는 `toJson()` 이다. 그 초안이 나중에 올라갈 때는
/// `walk_sync` 가 `WalkRepository.saveWalk` 를 지나므로 거기서 정책이 죽인다.
///
/// 이 구분이 없으면 검사가 로컬 저장까지 잡아서, 사람이 예외 목록에 파일 이름을
/// 하나씩 적기 시작한다 — 그러면 진짜 전송이 생겨도 그 목록에 숨는다.
List<({String path, String source})> _libSources() {
  final root = Directory('lib');
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

/// 이 파일이 요청을 만드는가.
///
/// ## `package:http` 만 보면 새어 나간다
///
/// `foryou_repository_impl.dart` 는 `api.postJson(...)` 이라는 **래퍼**를 쓴다.
/// 그 파일에는 `package:http` 도 `AuthedClient` 도 없어서 예전 검사가 통째로
/// 놓쳤다 — 좌표를 본문에 싣는데도.
///
/// 그래서 **경로 문자열**도 본다. 이 저장소에서 요청은 전부 `'/api/...'` 를 적어
/// 만든다. 래퍼가 몇 겹이든 그 문자열은 부르는 쪽에 남는다.
bool _makesRequest(String source) =>
    RegExp(r"""['\"]/api/""").hasMatch(source) ||
    source.contains('package:http') ||
    source.contains('AuthedClient');

/// 좌표를 **싣는** 모양. 읽는 것(`j['lat']`)은 들어오는 값이라 안 센다.
///
/// 셋을 본다 — `'lat': v` · `params['lat'] = v` · 쿼리 조립. 가운데 것이
/// `emotion_map_repository.dart` 의 모양이고, 예전 정규식은 그것을 놓쳤다.
final _writesCoordinate = RegExp(
    r"""['\"](lat|lng|latitude|longitude|userLat|userLng)['\"]\s*:"""
    r"""|\[\s*['\"](lat|lng|latitude|longitude)['\"]\s*\]\s*="""
    r"""|(lat|lng)=\$""",
    caseSensitive: false);

/// 정책을 안 지나도 되는 파일 — **이유와 함께** 적는다.
///
/// 이유를 적게 하는 것이 이 목록의 요점이다. 파일 이름만 늘어나는 목록은 다음 사람이
/// 그냥 한 줄 더 적고 지나간다.
///
/// 여기 있는 것은 전부 `lib/features/` 의 **레거시 셸**이다. v2 화면 어디에서도 그리로
/// 가지 않는 것을 `legacy_shell_reachability_test.dart` 가 따로 잠근다 — 그 잠금이
/// 풀리면 이 예외의 근거도 함께 사라진다.
const Map<String, String> _exempt = {
  'lib/features/emotion_map/data/emotion_map_repository.dart':
      '감정 지도의 주변 조회·검색. GET /api/curation/places/* 에 현위치를 쿼리로 싣는다. '
          'v2 에서 도달 불가이고, 이 셸의 처분은 #174 가 정한다 — 지금 정책을 끼워 넣으면 '
          '버릴지도 모르는 코드에 손을 대는 것이다.',
  'lib/features/foryou_v2/data/foryou_repository_impl.dart':
      '감정 추천. POST /api/curation/recommend 본문에 userLat·userLng 를 싣는다. '
          '위와 같은 셸이고 같은 이유다.',
};

void main() {
  group('소스 — 좌표를 보내는 자리가 정책을 지난다', () {
    test('요청에 좌표를 싣는 파일은 정책을 부른다 — lib 전체를 본다', () {
      final offenders = <String>[];

      for (final f in _libSources()) {
        if (f.path.endsWith('location_upload_policy.dart')) continue;
        if (_exempt.containsKey(f.path)) continue;
        if (!_makesRequest(f.source)) continue;

        // 쿼리·본문에 좌표 키를 싣는 모양. 파싱(`j['lat']`)은 들어오는 값이라 제외한다.
        if (!_writesCoordinate.hasMatch(f.source)) continue;

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

      for (final f in _libSources()) {
        if (f.path.endsWith('location_upload_policy.dart')) continue;
        if (_exempt.containsKey(f.path)) continue;
        if (!_makesRequest(f.source)) continue;
        if (!RegExp(r"""['"]path['"]\s*:|['"]pathT['"]\s*:""").hasMatch(f.source)) {
          continue;
        }
        if (!f.source.contains('LocationUploadPolicy')) offenders.add(f.path);
      }

      expect(offenders, isEmpty,
          reason: 'path·pathT 는 산책 전 구간의 원시 좌표열이다 — 집과 직장을 그대로 그린다');
    });

    test('예외 목록에 죽은 항목이 없다 — 남으면 그 파일이 규칙 밖에 영원히 남는다', () {
      final sources = {for (final f in _libSources()) f.path: f.source};
      final dead = <String>[];

      _exempt.forEach((path, reason) {
        final source = sources[path];
        if (source == null) {
          dead.add('$path (파일이 없다)');
          return;
        }
        if (!_makesRequest(source) || !_writesCoordinate.hasMatch(source)) {
          dead.add('$path (더 이상 좌표를 안 싣는다 — 예외를 지워라)');
        }
      });

      expect(dead, isEmpty,
          reason: '예외가 죽은 채 남으면, 그 파일에 새 전송이 생겨도 검사가 눈감아 준다');
    });

    test('예외는 레거시 셸뿐이고 이유가 적혀 있다 — v2 에는 예외가 없다', () {
      _exempt.forEach((path, reason) {
        expect(path, startsWith('lib/features/'),
            reason: 'v2 에 예외를 두면 그 순간 이 검사가 뜻을 잃는다. 살아 있는 화면의 '
                '전송은 정책을 지나야 한다');
        expect(reason.length, greaterThan(40),
            reason: '「괜찮음」 은 이유가 아니다. 무엇과 무엇을 견줘서 괜찮은지 적어라');
      });

      expect(File('test/app/legacy_shell_reachability_test.dart').existsSync(), isTrue,
          reason: '예외의 근거가 「v2 에서 도달 불가」 다. 그것을 잠그는 검사가 사라지면 '
              '이 예외들도 함께 다시 봐야 한다');
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
    final offenders = _libSources()
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

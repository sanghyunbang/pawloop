// 크루 저장소 — **왕복의 모양**을 잠근다 (이슈 #417, 서버는 PR #426).
//
// ## 여기서 가장 중요한 것
//
// **409 를 한 가지로 뭉개지 않는 것**이다. 정원이 찬 것과 초대코드를 다 쓴 것이 같은
// 상태로 오는데, 사용자가 할 일이 정반대다 — 하나는 **자리가 나기를 기다리는 것**이고
// 하나는 **새 코드를 받는 것**이다. "새 코드를 받으세요" 라고 말하면 정원이 찬 방에
// 코드를 다시 받아 와서 또 실패한다.
//
// 그다음이 **고치기의 `null` 과 `''` 를 안 섞는 것**이다. 안 보낸 필드는 안 바뀌고 빈
// 문자열은 지운다 — 섞으면 정원만 줄이려던 요청이 이름을 되돌린다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/crew_repository.dart';
import 'package:heat_trip_flutter/v2/domain/crew.dart';

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

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _error(int status, String code, String message) =>
    _json({'error': {'code': code, 'message': message, 'traceId': null}}, status: status);

Map<String, Object?> _crew({
  int id = 4,
  int roomId = 9,
  String name = '성수동 아침 산책',
  Object? intro = '천천히 걷습니다',
  Object? neighborhoodCode = '1120052000',
  String visibility = 'invite',
  int capacity = 20,
  int memberCount = 3,
  bool mine = true,
  bool owner = false,
  List<Object?> members = const [],
}) =>
    {
      'id': id,
      'roomId': roomId,
      'name': name,
      'intro': intro,
      'neighborhoodCode': neighborhoodCode,
      'visibility': visibility,
      'capacity': capacity,
      'memberCount': memberCount,
      'mine': mine,
      'owner': owner,
      'members': members,
      'createdAt': '2026-09-10T02:20:00Z',
    };

({CrewRepository repo, List<http.Request> sent}) fixture(
    Future<http.Response> Function(http.Request request) handler) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return handler(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CrewRepository(baseUrl: _base, client: client), sent: sent);
}

void main() {
  group('목록', () {
    test('scope 를 안 주면 내 크루다 — 크루 화면을 여는 사람 대부분이 든 모임을 보러 온다', () async {
      final f = fixture((_) async => _json([_crew()]));

      await f.repo.list();

      expect(f.sent.single.url.path, '/api/crews');
      expect(f.sent.single.url.queryParameters['scope'], 'mine');
    });

    test('우리 동네는 scope=neighborhood 로 나간다 — 좌표를 안 보낸다', () async {
      final f = fixture((_) async => _json(const []));

      await f.repo.list(scope: CrewScope.neighborhood);

      final uri = f.sent.single.url;
      expect(uri.queryParameters['scope'], 'neighborhood');
      expect(uri.query.contains('lat'), isFalse,
          reason: '동네는 행정동 코드로 찾는다 — 좌표는 기기를 안 떠난다(A안 #235)');
      expect(uri.query.contains('lng'), isFalse);
    });

    test('한 줄이 이상해도 나머지는 산다 — 목록 전체를 잃지 않는다', () async {
      final f = fixture((_) async => _json([
            _crew(id: 1),
            {'id': 2}, // roomId 가 없다
            _crew(id: 3),
          ]));

      final crews = await f.repo.list();

      expect(crews.map((c) => c.id), [1, 3]);
    });

    test('동네를 안 고르면 400 이고 invalid 다 — 화면이 "동네 고르기" 로 보낸다', () async {
      final f = fixture(
          (_) async => _error(400, 'VALIDATION', '동네를 먼저 골라 주세요.'));

      await expectLater(
        f.repo.list(scope: CrewScope.neighborhood),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.invalid)
            .having((e) => e.message, 'message', '동네를 먼저 골라 주세요.')),
      );
    });
  });

  group('만들기', () {
    test('동네를 안 주면 본문에 아예 안 싣는다 — 서버가 내 동네를 쓴다', () async {
      final f = fixture((_) async => _json(_crew(), status: 201));

      await f.repo.create(name: '성수동 아침 산책');

      final body = jsonDecode(f.sent.single.body) as Map;
      expect(body['name'], '성수동 아침 산책');
      expect(body.containsKey('neighborhoodCode'), isFalse,
          reason: '빈 값을 보내면 서버가 "지운다" 로 읽을 여지가 생긴다');
      expect(body['visibility'], 'invite', reason: '기본은 초대다');
      expect(body['capacity'], 20);
    });

    test('빈 소개는 안 싣는다', () async {
      final f = fixture((_) async => _json(_crew(), status: 201));

      await f.repo.create(name: '모임', intro: '');

      expect((jsonDecode(f.sent.single.body) as Map).containsKey('intro'), isFalse);
    });

    test('만 14세 미만은 403 이고 forbidden 이다', () async {
      final f = fixture((_) async =>
          _error(403, 'FORBIDDEN', '만 14세 미만은 크루에 참여할 수 없습니다.'));

      await expectLater(
        f.repo.create(name: '모임'),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.forbidden)
            .having((e) => e.message, 'message', '만 14세 미만은 크루에 참여할 수 없습니다.')),
      );
    });
  });

  group('고치기', () {
    test('안 준 필드는 본문에 없다 — 정원만 줄이는 요청이 이름을 되돌리지 않는다', () async {
      final f = fixture((_) async => _json(_crew(capacity: 8)));

      await f.repo.edit(4, capacity: 8);

      expect(f.sent.single.method, 'PATCH');
      expect(jsonDecode(f.sent.single.body), {'capacity': 8});
    });

    test('빈 문자열은 싣는다 — 그것이 "지운다" 의 유일한 표현이다', () async {
      final f = fixture((_) async => _json(_crew(intro: null)));

      await f.repo.edit(4, intro: '');

      expect(jsonDecode(f.sent.single.body), {'intro': ''});
    });

    test('아무것도 안 주면 왕복을 아예 안 보낸다', () async {
      final f = fixture((_) async => _json(_crew()));

      await expectLater(
        f.repo.edit(4),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.invalid)),
      );
      expect(f.sent, isEmpty,
          reason: '아무것도 안 바뀐 왕복을 보내고 400 을 받아 "고치지 못했어요" 를 띄우면 거짓말이다');
    });

    test('방장이 아니면 403 이다', () async {
      final f = fixture((_) async => _error(403, 'FORBIDDEN', '방장만 할 수 있습니다.'));

      await expectLater(
        f.repo.edit(4, name: '새 이름'),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.forbidden)),
      );
    });
  });

  group('참여', () {
    test('공개 참여는 크루 경로로, 코드 참여는 코드 경로로 간다', () async {
      final f = fixture((_) async => _json(_crew(mine: true)));

      await f.repo.join(4);
      await f.repo.joinByCode('K7QF2M9X');

      expect(f.sent[0].url.path, '/api/crews/4/members/me');
      expect(f.sent[0].method, 'POST');
      expect(f.sent[1].url.path, '/api/crews/join/K7QF2M9X');
      expect(f.sent[1].method, 'POST');
    });

    test('정원이 찬 409 와 코드를 다 쓴 409 가 다른 종류다 — 사용자가 할 일이 반대다', () async {
      final full = fixture((_) async => _error(409, 'CONFLICT', '크루 정원이 찼습니다.'));
      final roomFull =
          fixture((_) async => _error(409, 'ROOM_MEMBER_LIMIT', '방 정원이 찼습니다.'));
      final exhausted = fixture((_) async =>
          _error(409, 'INVITE_USES_EXHAUSTED', '초대코드의 사용 횟수를 모두 썼습니다.'));

      await expectLater(
        full.repo.join(4),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.full)),
      );
      await expectLater(
        roomFull.repo.join(4),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.full)),
      );
      await expectLater(
        exhausted.repo.joinByCode('K7QF2M9X'),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.inviteDead)),
      );
    });

    test('만료·회수된 코드는 410 이고 inviteDead 다', () async {
      final f = fixture((_) async => _error(410, 'INVITE_EXPIRED', '만료된 초대코드입니다.'));

      await expectLater(
        f.repo.joinByCode('K7QF2M9X'),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.inviteDead)),
      );
    });

    test('가족방 코드는 403 이다 — 크루 경로를 못 지나간다', () async {
      final f = fixture(
          (_) async => _error(403, 'FORBIDDEN', '이 방에는 참여할 수 없습니다.'));

      await expectLater(
        f.repo.joinByCode('FAMILY01'),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.forbidden)),
      );
    });

    test('초대 크루를 안 든 사람이 열면 404 다 — 403 으로 고쳐 말하지 않는다', () async {
      final f = fixture((_) async => _error(404, 'NOT_FOUND', '크루를 찾을 수 없습니다.'));

      await expectLater(
        f.repo.detail(4),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.notFound)),
      );
    });
  });

  group('나가기 · 내보내기 · 초대', () {
    test('나가기와 내보내기가 다른 경로다 — 재입장 금지가 걸리는 쪽이 다르다', () async {
      final f = fixture((_) async => http.Response('', 204));

      await f.repo.leave(4);
      await f.repo.kick(4, 77);

      expect(f.sent[0].url.path, '/api/crews/4/members/me');
      expect(f.sent[1].url.path, '/api/crews/4/members/77');
      expect(f.sent.every((r) => r.method == 'DELETE'), isTrue);
    });

    test('방장이 나가려 하면 400 이다', () async {
      final f = fixture(
          (_) async => _error(400, 'VALIDATION', '방장은 방을 나갈 수 없습니다.'));

      await expectLater(
        f.repo.leave(4),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.invalid)
            .having((e) => e.message, 'message', '방장은 방을 나갈 수 없습니다.')),
      );
    });

    test('초대 코드는 크루가 아니라 **방** 경로로 낸다 (ADR-0011)', () async {
      final f = fixture((_) async => _json({
            'code': 'K7QF2M9X',
            'expiresAt': '2026-09-17T02:20:00Z',
            'maxUses': null,
          }, status: 201));

      final invite = await f.repo.issueInvite(9);

      expect(f.sent.single.url.path, '/api/chat/rooms/9/invites',
          reason: '초대코드는 크루가 아니라 방에 붙는다 — 크루 쪽에 또 파면 코드가 두 종류가 된다');
      expect(invite.code, 'K7QF2M9X');
      expect(invite.maxUses, isNull);
    });
  });

  group('파싱', () {
    test('모르는 공개 범위는 초대로 떨어진다 — 안 열린 모임이 열린 것처럼 보이면 안 된다', () {
      final crew = Crew.tryParse(_crew(visibility: 'secret'))!;

      expect(crew.visibility, CrewVisibility.invite);
    });

    test('정원이 찼는지는 내가 든 크루면 묻지 않는다 — 이미 자리를 쓰고 있다', () {
      final full = Crew.tryParse(_crew(mine: false, capacity: 3, memberCount: 3))!;
      final joined = Crew.tryParse(_crew(mine: true, capacity: 3, memberCount: 3))!;

      expect(full.isFull, isTrue);
      expect(joined.isFull, isFalse);
    });

    test('빈 소개는 null 이다 — 화면이 "" 를 소개로 그리지 않는다', () {
      expect(Crew.tryParse(_crew(intro: '  '))!.intro, isNull);
      expect(Crew.tryParse(_crew(intro: null))!.intro, isNull);
    });

    test('createdAt 은 오프셋을 읽어 기기 시각으로 눕힌다', () {
      final crew = Crew.tryParse(_crew())!;

      expect(crew.createdAt, isNotNull);
      expect(crew.createdAt!.isUtc, isFalse);
      expect(crew.createdAt!.toUtc(), DateTime.utc(2026, 9, 10, 2, 20));
    });

    test('멤버 한 줄이 이상해도 나머지는 산다', () {
      final crew = Crew.tryParse(_crew(members: [
        {'userId': 1, 'nickname': '성수아빠', 'role': 'OWNER'},
        {'nickname': '이름만'},
        {'userId': 2, 'nickname': '이웃', 'role': 'MEMBER'},
      ]))!;

      expect(crew.members.map((m) => m.userId), [1, 2]);
      expect(crew.members.first.isOwner, isTrue);
      expect(crew.members.last.isOwner, isFalse);
    });
  });
}

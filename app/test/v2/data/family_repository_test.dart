// FamilyRepository — 네 경로의 요청 모양과 **실패의 종류** 를 잠근다 (이슈 #76).
//
// 실제 네트워크를 타지 않는다. `AuthedClient` 에 `MockClient` 를 꽂아 요청을 가로챈다 —
// `authed_client_test.dart` 가 쓰는 방식 그대로다(이 저장소에는 mockito 가 없다, 정책 #21).
//
// 여기서 재는 것은 셋이다.
//  1. 경로·메서드·본문이 계약(`openapi.yaml`)과 같은가.
//  2. 상태 코드가 **실패의 종류**로 옮겨지는가. `null` 하나로 뭉치면 "비행기 모드" 와
//     "아직 가족이 없다" 와 "남의 가족이다" 가 화면에서 같은 빈 칸이 된다.
//  3. `Authorization` 을 여기서 만들지 않는가 — 헤더는 `AuthedClient` 가 붙인다(#11).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';

const _base = 'https://api.example.test';

/// 메모리 위의 토큰 저장소. `flutter_secure_storage` 는 플랫폼 채널이라 테스트에서 못 쓴다.
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

/// 마지막 요청을 붙잡아 두는 저장소 한 벌.
({FamilyRepository repo, List<http.Request> seen}) repositoryThatAnswers(
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
  return (repo: FamilyRepository(baseUrl: _base, client: client), seen: seen);
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('경로와 본문이 계약과 같다', () {
    test('GET /api/groups/{id}/care-logs — 응답을 CareLogEntry 로 읽는다', () async {
      final f = repositoryThatAnswers((_) => _json([
            {
              'id': 7,
              'dogId': null,
              'groupId': 3,
              'type': 'meal',
              'doneBy': {'userId': 11, 'nickname': '아빠'},
              'occurredAt': '2026-08-30T14:20:00',
              'memo': '사료 반 컵',
            }
          ]));

      final logs = await f.repo.careLogs(3);

      expect(f.seen.single.url.path, '/api/groups/3/care-logs');
      expect(f.seen.single.method, 'GET');
      expect(logs.single.type, ServerCareType.meal);
      expect(logs.single.doneByName, '아빠');
      expect(
        logs.single.timeLabel,
        '14:20',
        reason: '확인 문구와 카드가 같은 표기를 써야 한다 — 시각 포맷이 두 곳에 있으면 갈린다',
      );
    });

    test('POST care-logs 는 type 만 보낸다 — 수행자와 시각은 서버가 정한다', () async {
      final f = repositoryThatAnswers((_) => _json({
            'id': 1,
            'type': 'walk',
            'doneBy': {'userId': 2, 'nickname': '엄마'},
            'occurredAt': '2026-08-30T19:05:00',
          }, status: 201));

      await f.repo.recordCare(3, ServerCareType.walk);

      final sent = jsonDecode(f.seen.single.body) as Map<String, dynamic>;
      expect(
        sent.keys,
        ['type'],
        reason: 'doneBy·occurredAt 을 보내면 남의 이름으로 기록을 남기거나 오늘 것을 어제로 밀 수 있다',
      );
      expect(
        sent['type'],
        'walk',
        reason: '계약·DB CHECK·앱이 같은 소문자 한 벌을 쓴다 — Dart enum 이름을 그대로 보내면 안 된다',
      );
    });

    test('PUT walk-notes 는 {notes:[...]} 가 아니라 {body:"..."} 다', () async {
      final f = repositoryThatAnswers((_) => _json({'groupId': 3, 'body': 'a\nb'}));

      await f.repo.replaceWalkNote(3, 'a\nb');

      expect(f.seen.single.method, 'PUT');
      expect(
        jsonDecode(f.seen.single.body),
        {'body': 'a\nb'},
        reason: '계약이 예전에 목록이었다 — 서버는 그룹당 메모 한 장을 안다',
      );
    });

    test('GET /api/groups/me — 구성원과 roomId 를 계약대로 읽는다', () async {
      final f = repositoryThatAnswers((_) => _json({
            'id': 3,
            'name': '보리네 가족',
            'roomId': 9,
            'members': [
              {'userId': 11, 'nickname': '아빠', 'role': 'OWNER'},
              {'userId': 12, 'nickname': '엄마', 'role': 'MEMBER'},
            ],
          }));

      final group = await f.repo.myGroup();

      expect(f.seen.single.url.path, '/api/groups/me');
      expect(group.id, 3);
      expect(
        group.roomId,
        9,
        reason: '초대 발급이 이 값으로 간다 — 틀리면 남의 방 코드를 발급하거나 403 이 된다',
      );
      expect(group.members.map((m) => m.nickname), ['아빠', '엄마']);
      expect(
        group.members.map((m) => m.isOwner),
        [true, false],
        reason: 'isOwner 는 대문자 OWNER 문자열 비교다. 서버가 소문자로 바뀌면 모두가 '
            '조용히 "가족" 으로 보이고 초대 버튼이 사라진다 — 그 회귀를 여기서 잡는다',
      );
      expect(group.members.first.userId, 11);
    });

    test('members 가 없거나 모양이 다르면 빈 목록이다 — 화면 전체가 죽지 않는다', () async {
      final f = repositoryThatAnswers((_) => _json({'id': 3, 'name': '보리네'}));

      final group = await f.repo.myGroup();

      expect(group.members, isEmpty);
      expect(group.roomId, 0, reason: 'roomId 가 없으면 0 이다 — null 역참조로 죽지 않는다');
    });

    test('초대 발급은 그룹이 아니라 방 경로다 — 초대코드는 방에 붙는다(ADR-0011)', () async {
      final f = repositoryThatAnswers((_) => _json({'code': 'ABCDE-FGHIJ'}, status: 201));

      final code = await f.repo.issueInvite(42);

      expect(f.seen.single.url.path, '/api/chat/rooms/42/invites');
      expect(code, 'ABCDE-FGHIJ');
    });
  });

  group('상태 코드를 실패의 종류로 옮긴다', () {
    test('GET /api/groups/me 404 는 오류가 아니라 "아직 가족이 없다" 다', () async {
      final f = repositoryThatAnswers((_) => _json({'error': {}}, status: 404));

      expect(
        () => f.repo.myGroup(),
        throwsA(isA<FamilyFailure>()
            .having((e) => e.kind, 'kind', FamilyFailureKind.noGroup)),
      );
    });

    test('403 은 forbidden — 남의 가족이다', () async {
      final f = repositoryThatAnswers((_) => _json({'error': {}}, status: 403));

      expect(
        () => f.repo.careLogs(3),
        throwsA(isA<FamilyFailure>()
            .having((e) => e.kind, 'kind', FamilyFailureKind.forbidden)),
      );
    });

    test('400 은 invalid — "연결이 불안정해요 · 다시 시도" 가 아니다', () async {
      final f = repositoryThatAnswers((_) => _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': '산책 주의사항은 500자 이하여야 합니다.',
            }
          }, status: 400));

      await expectLater(
        () => f.repo.replaceWalkNote(3, '가' * 501),
        throwsA(isA<FamilyFailure>()
            .having((e) => e.kind, 'kind', FamilyFailureKind.invalid)
            .having(
              (e) => e.message,
              'message',
              contains('500자'),
              // 400 을 network 로 떨어뜨리면 화면은 "연결이 불안정해요 · 다시 시도" 를 그린다.
              // 네트워크는 멀쩡하고 다시 눌러도 영원히 같은 결과라, 사용자가 할 수 있는 일이
              // 화면 어디에도 없다. 이 저장소가 FamilyFailure 를 만든 이유가 바로 그거다.
            )),
      );
    });

    test('429 는 rateLimited — 다시 시도하면 되는 상태다', () async {
      final f = repositoryThatAnswers((_) => _json({'error': {}}, status: 429));

      expect(
        () => f.repo.recordCare(3, ServerCareType.meal),
        throwsA(isA<FamilyFailure>()
            .having((e) => e.kind, 'kind', FamilyFailureKind.rateLimited)),
      );
    });

    test('연결이 끊기면 network — 화면이 "다시 시도" 를 그릴 수 있어야 한다', () async {
      final client = AuthedClient(
        inner: MockClient((_) async => throw http.ClientException('끊김')),
        baseUrl: _base,
        store: _FakeTokenStore(),
      );
      final repo = FamilyRepository(baseUrl: _base, client: client);

      expect(
        () => repo.careLogs(3),
        throwsA(isA<FamilyFailure>()
            .having((e) => e.kind, 'kind', FamilyFailureKind.network)),
      );
    });
  });

  group('WalkNoteSheet — 한 장과 목록 사이', () {
    test('빈 줄은 항목이 아니다 — 지울 수도 없는 빈 칸이 남는다', () {
      const sheet = WalkNoteSheet(body: '계단 피하기\n\n  \n리드줄 짧게');

      expect(sheet.lines, ['계단 피하기', '리드줄 짧게']);
    });

    test('목록을 되돌리면 서버가 아는 한 장이 된다', () {
      expect(WalkNoteSheet.fromLines(['a', '  ', 'b']), 'a\nb');
    });

    test('아직 아무도 안 쓴 그룹은 빈 본문이다 — 404 가 아니다', () async {
      final f = repositoryThatAnswers((_) => _json({
            'groupId': 3,
            'body': '',
            'updatedBy': null,
            'updatedAt': null,
          }));

      final note = await f.repo.walkNote(3);

      expect(note.body, isEmpty);
      expect(note.updatedByName, isNull);
    });
  });

  test('모르는 케어 종류는 목록에서 조용히 빠진다 — 화면 전체가 죽지 않는다', () async {
    final f = repositoryThatAnswers((_) => _json([
          {
            'id': 1,
            'type': 'grooming',
            'doneBy': {'userId': 1, 'nickname': '나'},
            'occurredAt': '2026-08-30T09:00:00',
          },
          {
            'id': 2,
            'type': 'water',
            'doneBy': {'userId': 1, 'nickname': '나'},
            'occurredAt': '2026-08-30T09:10:00',
          },
        ]));

    final logs = await f.repo.careLogs(3);

    expect(
      logs.map((l) => l.type),
      [ServerCareType.water],
      reason: '서버가 종류를 늘렸는데 앱이 낡았을 때 카드 한 칸이 안 그려지는 것과 '
          '화면 전체가 죽는 것은 다르다',
    );
  });
}

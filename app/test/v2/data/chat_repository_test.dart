import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 채팅 API 의 요청·응답 처리. (이슈 #81)
///
/// 실제 네트워크를 타지 않는다. `MockClient` 가 요청을 받아 원하는 응답을 돌려준다.
/// 여기서 지키는 것은 셋이다 — **무엇을 보내는가**(델타 커서·멱등키·ETag),
/// **304 를 어떻게 읽는가**, **초대 실패 넷을 어떻게 가르는가**.
const String _base = 'https://api.test';

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

ChatRepository _repo(MockClient inner) => ChatRepository(
      baseUrl: _base,
      client: AuthedClient(inner: inner, baseUrl: _base, store: _FakeTokenStore()),
    );

/// 서버가 실제로 주는 모양.
///
/// **charset 을 빠뜨리면 안 된다.** `http.Response` 는 charset 이 없으면 본문을 latin-1 로
/// 담고, 그러면 한글이 `utf8.decode` 에서 깨져 네트워크 오류로 둔갑한다. 서버는 언제나
/// `application/json; charset=utf-8` 을 준다 — 테스트가 서버를 잘못 흉내 내면 안 된다.
http.Response _json(Object body, int status, {Map<String, String>? extraHeaders}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?extraHeaders,
    },
  );
}

void main() {
  group('방 목록', () {
    test('서버가 계산한 unread 를 그대로 쓴다 — 앱이 빼기를 다시 하면 두 곳이 갈린다', () async {
      final repo = _repo(MockClient((req) async {
        expect(req.url.path, '/api/chat/rooms');
        return _json([
          {
            'id': 7,
            'title': '우리 가족',
            'tag': '가족',
            'lastSeq': 42,
            'lastReadSeq': 40,
            'unread': 2,
            'memberCount': 3,
            'lastMessage': {'body': '사료 사갈게', 'senderName': '아빠'},
          }
        ], 200);
      }));

      final rooms = await repo.rooms();

      expect(rooms, hasLength(1));
      expect(rooms.single.unread, 2);
      expect(rooms.single.tag, '가족');
      expect(rooms.single.lastMessageBody, '사료 사갈게');
    });

    test('모양이 깨진 방은 버리고 나머지를 살린다 — 하나 때문에 목록이 통째로 비면 안 된다', () async {
      final repo = _repo(MockClient((req) async => _json([
            {'title': 'id 가 없는 방'},
            {'id': 9, 'title': '멀쩡한 방', 'tag': '산책 크루', 'unread': 0, 'memberCount': 2},
          ], 200)));

      final rooms = await repo.rooms();

      expect(rooms, hasLength(1));
      expect(rooms.single.id, 9);
    });
  });

  group('델타 폴링', () {
    test('afterSeq 를 보낸다 — id 를 보내지 않는다', () async {
      late Uri seen;
      final repo = _repo(MockClient((req) async {
        seen = req.url;
        return _json({'items': <Object>[], 'lastSeq': 42, 'hasMore': false}, 200);
      }));

      await repo.messages(7, afterSeq: 42);

      expect(seen.queryParameters['afterSeq'], '42');
      expect(
        seen.queryParameters.containsKey('id'),
        isFalse,
        reason: '''
id 는 전역 시퀀스라 방 안에서 연속이 아니다. 그것을 커서로 쓰면 다른 방의 메시지가
끼어든 만큼 건너뛴다 (ADR-0011).''',
      );
    });

    test('ETag 를 받으면 다음 요청에 If-None-Match 로 되돌려 보낸다', () async {
      final headersSeen = <Map<String, String>>[];
      final repo = _repo(MockClient((req) async {
        headersSeen.add(req.headers);
        return _json(
          {'items': <Object>[], 'lastSeq': 42, 'hasMore': false},
          200,
          extraHeaders: {'etag': '"7:42"'},
        );
      }));

      final first = await repo.messages(7, afterSeq: 41);
      expect(first.etag, '"7:42"');

      await repo.messages(7, afterSeq: 42, etag: first.etag);

      expect(
        headersSeen.last['If-None-Match'] ?? headersSeen.last['if-none-match'],
        '"7:42"',
      );
    });

    test('304 는 오류가 아니라 빈 응답이다 — 폴링에서는 이게 정상이다', () async {
      final repo = _repo(MockClient((req) async => http.Response('', 304)));

      final page = await repo.messages(7, afterSeq: 42, etag: '"7:42"');

      expect(page.notModified, isTrue);
      expect(page.messages, isEmpty);
      expect(page.isEmpty, isTrue, reason: '폴링 간격을 늘릴지의 입력이 된다');
      expect(page.etag, '"7:42"', reason: '다음 요청에도 같은 ETag 를 써야 한다');
    });

    test('새 메시지가 오면 비어 있지 않다', () async {
      final repo = _repo(MockClient((req) async => _json({
            'items': [
              {
                'id': 100,
                'roomSeq': 43,
                'senderUserId': 5,
                'senderName': '엄마',
                'body': '안녕',
              }
            ],
            'lastSeq': 43,
            'hasMore': false,
          }, 200)));

      final page = await repo.messages(7, afterSeq: 42);

      expect(page.isEmpty, isFalse);
      expect(page.messages.single.roomSeq, 43);
      expect(page.messages.single.body, '안녕');
    });
  });

  group('전송', () {
    test('멱등키를 본문에 실어 보낸다', () async {
      late Map<String, dynamic> body;
      final repo = _repo(MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'id': 1,
          'roomSeq': 44,
          'senderUserId': 1,
          'senderName': '나',
          'body': '보리 밥 줬어요',
        }, 201);
      }));

      final sent = await repo.send(7, '보리 밥 줬어요', 'KEY-1');

      expect(body['clientMsgId'], 'KEY-1');
      expect(body['body'], '보리 밥 줬어요');
      expect(sent.roomSeq, 44, reason: '순서는 서버가 배정한 값이 진실이다');
    });
  });

  group('초대 실패 네 가지 — 완료 조건 4', () {
    Future<ChatFailureKind> joinFailure(int status, String code) async {
      final repo = _repo(MockClient((req) async => _json({
            'error': {'code': code, 'message': '서버 문구', 'traceId': 't-1'}
          }, status)));
      try {
        await repo.joinByInviteCode('ABC');
        fail('실패해야 한다');
      } on ChatFailure catch (e) {
        return e.kind;
      }
    }

    test('만료 · 회수 · 소진 · 정원 초과가 각각 다른 종류다', () async {
      expect(await joinFailure(410, 'INVITE_EXPIRED'), ChatFailureKind.inviteExpired);
      expect(await joinFailure(410, 'INVITE_REVOKED'), ChatFailureKind.inviteRevoked);
      expect(await joinFailure(409, 'INVITE_USES_EXHAUSTED'), ChatFailureKind.inviteExhausted);
      expect(await joinFailure(409, 'ROOM_MEMBER_LIMIT'), ChatFailureKind.roomFull);
    });

    test('넷의 문구가 서로 다르다 — 하나로 뭉치면 사용자가 할 일을 모른다', () {
      final messages = {
        ChatFailure.messageFor(ChatFailureKind.inviteExpired),
        ChatFailure.messageFor(ChatFailureKind.inviteRevoked),
        ChatFailure.messageFor(ChatFailureKind.inviteExhausted),
        ChatFailure.messageFor(ChatFailureKind.roomFull),
      };

      expect(
        messages,
        hasLength(4),
        reason: '''
"코드를 다시 받아야 하는지" 와 "방장에게 자리를 비워 달라고 해야 하는지" 는 사용자가
할 일이 다르다. 문구가 같으면 그것을 구분할 수 없다.''',
      );
    });

    test('상태 코드만 있고 error.code 가 없어도 보수적으로 가른다', () async {
      final repo = _repo(MockClient((req) async => http.Response('', 410)));

      try {
        await repo.joinByInviteCode('ABC');
        fail('실패해야 한다');
      } on ChatFailure catch (e) {
        expect(e.kind, ChatFailureKind.inviteExpired, reason: '410 은 그 코드로는 이제 안 된다는 뜻이다');
      }
    });
  });

  group('그 밖의 실패', () {
    test('429 는 네트워크 오류가 아니다 — 다시 눌러도 같은 결과라 문구가 달라야 한다', () async {
      final repo = _repo(MockClient((req) async => _json({
            'error': {'code': 'RATE_LIMITED', 'message': 'x', 'traceId': 't'}
          }, 429)));

      try {
        await repo.rooms();
        fail('실패해야 한다');
      } on ChatFailure catch (e) {
        expect(e.kind, ChatFailureKind.rateLimited);
      }
    });

    test('403 은 이 방의 멤버가 아니라는 뜻이다', () async {
      final repo = _repo(MockClient((req) async => http.Response('', 403)));

      try {
        await repo.messages(7);
        fail('실패해야 한다');
      } on ChatFailure catch (e) {
        expect(e.kind, ChatFailureKind.forbidden);
      }
    });
  });

  // ─────────────────────────── 신고 · 가리기 (이슈 #82) ───────────────────────────

  group('신고', () {
    test('고른 번호와 사유를 보낸다 — 사유는 계약의 wire 값이다', () async {
      Map<String, dynamic>? sent;
      String? path;
      final repo = _repo(MockClient((req) async {
        path = req.url.path;
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'reportId': 12, 'createdAt': '2026-08-31T10:00:00'}, 201);
      }));

      final id = await repo.report(
          7, [3, 4], ChatReportReason.sexual, memo: '  불쾌합니다  ');

      expect(id, 12);
      expect(path, '/api/chat/rooms/7/reports');
      expect(sent!['roomSeqs'], [3, 4]);
      expect(sent!['reason'], 'sexual',
          reason: 'enum 이름(SEXUAL)이 아니라 계약의 소문자 값이어야 한다');
      expect(sent!['memo'], '불쾌합니다', reason: '앞뒤 공백은 보내기 전에 턴다');
    });

    test('메모가 비면 아예 안 보낸다 — 빈 문자열을 저장할 이유가 없다', () async {
      Map<String, dynamic>? sent;
      final repo = _repo(MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'reportId': 1, 'createdAt': 'x'}, 201);
      }));

      await repo.report(7, [1], ChatReportReason.spam, memo: '   ');

      expect(sent!.containsKey('memo'), isFalse);
    });

    test('신고 오류 넷을 각각 다르게 가른다 — 사용자가 할 일이 다르다', () async {
      const cases = {
        'REPORT_EMPTY': ChatFailureKind.reportEmpty,
        'REPORT_MESSAGE_LIMIT': ChatFailureKind.reportTooMany,
        'REPORT_MIXED_SENDERS': ChatFailureKind.reportMixedSenders,
        'REPORT_SELF': ChatFailureKind.reportSelf,
      };

      for (final entry in cases.entries) {
        final repo = _repo(MockClient((req) async => _json({
              'error': {'code': entry.key, 'message': 'x', 'traceId': 't'}
            }, 400)));

        try {
          await repo.report(7, [1], ChatReportReason.abuse);
          fail('실패해야 한다: ${entry.key}');
        } on ChatFailure catch (e) {
          expect(e.kind, entry.value, reason: entry.key);
          expect(e.message, isNotEmpty);
        }
      }
    });

    test('사유 어휘가 계약과 같다 — 여기가 갈리면 서버가 400 을 낸다', () {
      expect(
        ChatReportReason.values.map((r) => r.wire).toList(),
        ['spam', 'abuse', 'sexual', 'fraud', 'other'],
      );
    });
  });

  group('가리기', () {
    test('가리기는 사람 단위다 — 경로에 방 id 가 없다', () async {
      String? path;
      Map<String, dynamic>? sent;
      final repo = _repo(MockClient((req) async {
        path = req.url.path;
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 201);
      }));

      await repo.block(42);

      expect(path, '/api/chat/blocks');
      expect(sent!['userId'], 42);
    });

    test('가리기 해제는 DELETE 고 204 를 성공으로 읽는다', () async {
      String? method;
      String? path;
      final repo = _repo(MockClient((req) async {
        method = req.method;
        path = req.url.path;
        return http.Response('', 204);
      }));

      await repo.unblock(42);

      expect(method, 'DELETE');
      expect(path, '/api/chat/blocks/42');
    });

    test('가려진 메시지는 목록에서 빠지지 않고 본문도 온다', () async {
      final repo = _repo(MockClient((req) async => _json({
            'items': [
              {
                'id': 1,
                'roomSeq': 5,
                'senderUserId': 9,
                'senderName': '가려진 사람',
                'body': '접히지만 사라지지는 않는 말',
                'createdAt': '2026-08-31T10:00:00',
                'hiddenByBlock': true,
              }
            ],
            'lastSeq': 5,
            'hasMore': false,
          }, 200)));

      final page = await repo.messages(7);

      expect(page.messages, hasLength(1),
          reason: '빼면 그 roomSeq 가 도달하지 않아 미읽음 뱃지가 영원히 남는다');
      expect(page.messages.single.hiddenByBlock, isTrue);
      expect(page.messages.single.body, '접히지만 사라지지는 않는 말',
          reason: '"보기" 를 누를 때 요청이 한 번 더 필요하지 않도록 본문이 함께 온다');
    });

    test('hiddenByBlock 이 없으면 false 다 — 옛 서버와도 화면이 그려져야 한다', () async {
      final repo = _repo(MockClient((req) async => _json({
            'items': [
              {'id': 1, 'roomSeq': 5, 'senderUserId': 9, 'senderName': 'x', 'body': 'y'}
            ],
            'lastSeq': 5,
            'hasMore': false,
          }, 200)));

      final page = await repo.messages(7);

      expect(page.messages.single.hiddenByBlock, isFalse);
    });

    test('방 목록 미리보기도 접힘 여부를 읽는다', () async {
      final repo = _repo(MockClient((req) async => _json([
            {
              'id': 1,
              'title': '가족',
              'tag': '가족',
              'lastSeq': 5,
              'lastReadSeq': 5,
              'unread': 0,
              'memberCount': 2,
              'lastMessage': {'body': '샐 뻔한 말', 'senderName': 'x', 'hiddenByBlock': true},
            }
          ], 200)));

      final rooms = await repo.rooms();

      expect(rooms.single.lastMessageHidden, isTrue,
          reason: '방 안에서 접어 놓고 목록에서 그대로 보여 주면 거기로 샌다');
    });
  });

  group('강퇴', () {
    test('강퇴와 재입장 금지 해제가 서로 다른 경로다', () async {
      final calls = <String>[];
      final repo = _repo(MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response('', 204);
      }));

      await repo.removeMember(7, 42);
      await repo.allowRejoin(7, 42);

      expect(calls, [
        'DELETE /api/chat/rooms/7/members/42',
        'DELETE /api/chat/rooms/7/bans/42',
      ]);
    });
  });
}

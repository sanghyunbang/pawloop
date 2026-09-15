// 반응의 전선 (#452) — 켜기·끄기가 어느 경로로 가고, 응답의 집계를 어떻게 읽는가.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';

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

/// 서버가 돌려주는 최신 집계 하나.
const _summary = '{"messageId":41,"reactions":['
    '{"kind":"like","count":2,"mine":true},'
    '{"kind":"check","count":1,"mine":false}]}';

ChatRepository _repo(void Function(http.Request request) seen, {String body = _summary}) =>
    ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          seen(request);
          return http.Response(body, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      ),
    );

void main() {
  test('켜기는 POST, 끄기는 DELETE — 같은 경로다', () async {
    http.Request? seen;
    await _repo((r) => seen = r).react(41, 'like');
    expect(seen!.method, 'POST');
    expect(seen!.url.path, '/api/chat/messages/41/reactions/like');

    await _repo((r) => seen = r).unreact(41, 'like');
    expect(seen!.method, 'DELETE',
        reason: '토글 하나면 재시도가 내 반응을 조용히 되돌린다 — 켜기와 끄기는 다른 요청이다');
    expect(seen!.url.path, '/api/chat/messages/41/reactions/like');
  });

  test('응답의 최신 집계를 순서 그대로 읽는다 — mine 은 종류마다 다르다', () async {
    final reactions = await _repo((_) {}).react(41, 'like');

    expect(reactions.map((r) => r.kind).toList(), ['like', 'check'],
        reason: '순서는 서버가 정한다 — 앱이 다시 정렬하면 같은 말이 기기마다 다르게 보인다');
    expect(reactions.first.count, 2);
    expect(reactions.first.mine, isTrue);
    expect(reactions.last.mine, isFalse);
  });

  test('메시지에 실려 온 반응을 읽는다 — 옛 서버(키 없음)는 빈 목록이다', () {
    final withReactions = ChatMessageItem.tryParse({
      'id': 7,
      'roomSeq': 3,
      'senderUserId': 8,
      'senderName': '보통 사람',
      'body': '보리 밥 줬어요',
      'createdAt': '2026-09-15T00:00:00Z',
      'hiddenByBlock': false,
      'reactions': [
        {'kind': 'check', 'count': 3, 'mine': true},
      ],
    });
    expect(withReactions!.reactions.single.count, 3);
    expect(withReactions.reactions.single.mine, isTrue);

    final old = ChatMessageItem.tryParse({
      'id': 7,
      'roomSeq': 3,
      'senderUserId': 8,
      'senderName': '보통 사람',
      'body': '보리 밥 줬어요',
      'createdAt': '2026-09-15T00:00:00Z',
      'hiddenByBlock': false,
    });
    expect(old!.reactions, isEmpty, reason: 'null 이 아니라 빈 목록이라야 같은 코드로 그린다');
  });

  test('withReactions 는 반응만 바꾼다 — 본문도 순서도 그대로다', () {
    const before = ChatMessageItem(
      id: 7,
      roomSeq: 3,
      senderUserId: 8,
      senderName: '보통 사람',
      body: '보리 밥 줬어요',
      createdAt: null,
      deleted: false,
      reactions: [ChatReaction(kind: 'like', count: 1, mine: false)],
    );

    final after = before.withReactions(
        const [ChatReaction(kind: 'like', count: 2, mine: true)]);

    expect(after.id, before.id);
    expect(after.roomSeq, before.roomSeq);
    expect(after.body, before.body);
    expect(after.reactions.single.count, 2);
    expect(after.reactions.single.mine, isTrue);
  });
}

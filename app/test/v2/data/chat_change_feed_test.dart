// 변경 피드의 전선 (ADR-0023, #500) — 커서를 싣고, `changed` 와 `lastChangeSeq` 를 읽고, 304 는 커서를 지키지 않는다.
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

/// 서버가 준 한 장. `changed` 에는 톰스톤 하나가 들어 있다.
const _bodyWithChange = '''
{"items":[],"lastSeq":7,"hasMore":false,
 "changed":[{"id":3,"roomId":4,"roomSeq":3,"senderUserId":8,"senderName":"보통 사람","contentType":"text",
             "body":"","createdAt":"2026-09-15T00:00:00Z","deletedAt":"2026-09-15T00:10:00Z","hiddenByBlock":false}],
 "lastChangeSeq":5}
''';

ChatRepository _repo(void Function(Uri uri) seen, {String body = _bodyWithChange, int status = 200}) =>
    ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          seen(request.url);
          return http.Response(status == 304 ? '' : body, status,
              headers: {'content-type': 'application/json; charset=utf-8', 'etag': '"4:7:5"'});
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      ),
    );

void main() {
  test('afterChangeSeq 를 주면 질의에 실린다 — 안 주면 키 자체가 없다', () async {
    Uri? seen;
    await _repo((u) => seen = u).messages(4, afterSeq: 7, afterChangeSeq: 0);
    expect(seen!.queryParameters['afterChangeSeq'], '0');

    await _repo((u) => seen = u).messages(4, afterSeq: 7);
    expect(seen!.queryParameters.containsKey('afterChangeSeq'), isFalse,
        reason: '첫 진입은 그 장이 이미 최신이라 받을 변화가 없다');
  });

  test('changed 와 lastChangeSeq 를 읽는다 — changed 는 messages 와 섞이지 않는다', () async {
    final page = await _repo((_) {}).messages(4, afterSeq: 7, afterChangeSeq: 0);

    expect(page.messages, isEmpty, reason: '새 말은 없다');
    expect(page.changed, hasLength(1));
    expect(page.changed.single.id, 3);
    expect(page.changed.single.deleted, isTrue);
    expect(page.lastChangeSeq, 5);
  });

  test('바뀐 말이 있으면 빈 폴링이 아니다 — 방이 조용한 것이 아니다', () async {
    final page = await _repo((_) {}).messages(4, afterSeq: 7, afterChangeSeq: 0);

    expect(page.isEmpty, isFalse);
  });

  test('옛 서버(changed 키 없음)는 빈 목록으로 읽는다 — 예전처럼 움직인다', () async {
    const old = '{"items":[],"lastSeq":7,"hasMore":false}';
    final page = await _repo((_) {}, body: old).messages(4, afterSeq: 7, afterChangeSeq: 0);

    expect(page.changed, isEmpty);
    expect(page.lastChangeSeq, 0);
    expect(page.isEmpty, isTrue);
  });

  test('304 는 커서를 그대로 돌려준다 — 0 으로 되돌리면 옛 변화를 다시 받는다', () async {
    final page = await _repo((_) {}, status: 304).messages(4, afterSeq: 7, afterChangeSeq: 5);

    expect(page.notModified, isTrue);
    expect(page.lastChangeSeq, 5);
    expect(page.changed, isEmpty);
  });
}

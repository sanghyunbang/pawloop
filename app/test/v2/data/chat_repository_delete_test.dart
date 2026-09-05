// 내 메시지 삭제 — 이슈 #197. 계약대로 부르고, 결과를 계약대로 읽는가.

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('DELETE /api/chat/messages/{id} 를 부르고 204 면 조용히 끝난다', () async {
    http.Request? sent;
    final repo = _repo(MockClient((req) async {
      sent = req;
      return http.Response('', 204);
    }));

    await repo.deleteMessage(42);

    expect(sent!.method, 'DELETE');
    expect(sent!.url.path, '/api/chat/messages/42');
    expect(sent!.headers['authorization'], 'Bearer AT-1', reason: '내 것만 지울 수 있으니 토큰이 실려야 한다');
  });

  test('이미 지운 메시지도 204 라 실패가 아니다 — 재시도가 안전하다', () async {
    final repo = _repo(MockClient((_) async => http.Response('', 204)));
    await repo.deleteMessage(42);
    await repo.deleteMessage(42);
  });

  test('남의 메시지(403)는 ChatFailure 다 — 화면이 이유를 보여 줄 수 있어야 한다', () async {
    final repo = _repo(MockClient((_) async => _json(
          '{"error":{"code":"FORBIDDEN","message":"보낸 사람만 지울 수 있습니다."}}', 403,
        )));

    expect(() => repo.deleteMessage(7), throwsA(isA<ChatFailure>()));
  });

  test('없는 메시지(404)도 ChatFailure 다', () async {
    final repo = _repo(MockClient((_) async => _json(
          '{"error":{"code":"NOT_FOUND","message":"메시지를 찾을 수 없습니다."}}', 404,
        )));

    expect(() => repo.deleteMessage(7), throwsA(isA<ChatFailure>()));
  });
}

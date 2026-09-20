// 기기 토큰 등록 — PUT /api/push/tokens (#83). 계약(openapi.yaml 의 PushTokenInput)대로 보내는가.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/push_token_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

PushTokenRepository _repo(MockClient inner, {String base = _base}) => PushTokenRepository(
      baseUrl: base,
      client: AuthedClient(inner: inner, baseUrl: _base, store: _FakeTokenStore()),
    );

void main() {
  test('PUT /api/push/tokens 에 token·platform 을 JSON 으로, Bearer 를 달고 — 204 면 true', () async {
    final seen = <http.Request>[];
    final repo = _repo(MockClient((req) async {
      seen.add(req);
      return http.Response('', 204);
    }));

    final ok = await repo.register('fcm-token-abc', platform: PushTokenRepository.android);

    expect(ok, isTrue);
    final req = seen.single;
    expect(req.method, 'PUT');
    expect(req.url.toString(), '$_base/api/push/tokens');
    expect(req.headers['authorization'], 'Bearer AT-1', reason: '주체는 토큰의 주인이다 — 경로에 사용자 id 가 없다');
    expect(req.headers['content-type'], AuthedClient.jsonContentType);
    expect(jsonDecode(req.body), {'token': 'fcm-token-abc', 'platform': 'android'},
        reason: '계약의 PushTokenInput — 서버가 platform 을 android|ios 패턴으로 거른다');
  });

  test('204 가 아니면 false — 던지지 않는다', () async {
    expect(await _repo(MockClient((_) async => http.Response('{"code":"BAD"}', 400)))
        .register('t', platform: PushTokenRepository.ios), isFalse);
    expect(await _repo(MockClient((_) async => http.Response('', 500)))
        .register('t', platform: PushTokenRepository.ios), isFalse);
  });

  test('네트워크가 끊겨도 false — 푸시는 덧이라 로그인·홈이 이것 때문에 막히면 안 된다', () async {
    final repo = _repo(MockClient((_) async => throw http.ClientException('끊김')));

    expect(await repo.register('t', platform: PushTokenRepository.android), isFalse);
  });

  test('baseUrl 끝의 / 는 지운다', () async {
    final seen = <http.Request>[];
    final repo = _repo(MockClient((req) async {
      seen.add(req);
      return http.Response('', 204);
    }), base: '$_base/');

    await repo.register('t', platform: PushTokenRepository.android);

    expect(seen.single.url.toString(), '$_base/api/push/tokens');
  });
}

// 산책 피드 — 게스트는 서버도 초안 큐도 보지 않는다 (#324).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  tearDown(AuthState.resetForTest);

  test('게스트면 요청 없이 guestData 를 준다 — offline 이 아니다', () async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    var calls = 0;
    final repo = WalkRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('{"error":{}}', 401);
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

    final data = await WalkFeed(repository: repo).load();

    expect(data.guest, isTrue);
    expect(data.offline, isFalse, reason: '부르지 않았으니 못 부른 것도 아니다');
    expect(data.walks, isEmpty);
    expect(data.pending, isEmpty);
    expect(calls, 0);
  });

  test('로그인 상태면 게스트 값이 아니다 — 서버를 부른다', () async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    var calls = 0;
    final repo = WalkRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('{"error":{}}', 500);
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

    final data = await WalkFeed(repository: repo).load();

    expect(data.guest, isFalse);
    expect(calls, greaterThan(0));
  });
}

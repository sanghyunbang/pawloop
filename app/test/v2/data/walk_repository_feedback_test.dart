// WalkRepository.rateInsight (#486 후속) — PUT 한 번, 본문은 value 하나, 지우기는 null 로.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

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

class _Seen {
  String? method;
  String? path;
  Map<String, dynamic>? body;
  int status = 200;
}

WalkRepository _repo(_Seen seen) => WalkRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          seen.method = request.method;
          seen.path = request.url.path;
          seen.body = jsonDecode(request.body) as Map<String, dynamic>;
          if (seen.status != 200) return http.Response('{"error":{"code":"NOT_FOUND"}}', seen.status);
          final value = seen.body!['value'];
          return http.Response(
            '{"id":7,"text":"이번 주는 3회 걸었어요.\\n좋아요.\\n한 번 더 어떠세요?","generatedAt":"2026-09-14T09:30:00Z",'
            '"feedback":${value == null ? 'null' : '"$value"'}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      ),
    );

void main() {
  test('👍 는 PUT /api/walks/insights/{id}/feedback 에 {"value":"up"} — 응답의 feedback 을 돌려준다', () async {
    final seen = _Seen();

    final saved = await _repo(seen).rateInsight(7, 'up');

    expect(seen.method, 'PUT');
    expect(seen.path, '/api/walks/insights/7/feedback');
    expect(seen.body, {'value': 'up'});
    expect(saved.id, 7);
    expect(saved.feedback, 'up');
  });

  test('지우기는 value 키를 빼지 않고 null 로 보낸다 — 키가 없으면 서버가 "안 보냈다" 로 읽는다', () async {
    final seen = _Seen();

    final saved = await _repo(seen).rateInsight(7, null);

    expect(seen.body!.containsKey('value'), isTrue);
    expect(seen.body!['value'], isNull);
    expect(saved.feedback, isNull);
  });

  test('404(남의 요약)는 WalkFailure 다 — 화면이 되돌린다', () async {
    final seen = _Seen()..status = 404;

    expect(() => _repo(seen).rateInsight(7, 'down'), throwsA(isA<WalkFailure>()));
  });
}

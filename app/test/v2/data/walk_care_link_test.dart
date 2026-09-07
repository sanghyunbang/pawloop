// 산책 저장 → 오늘의 케어 "산책" 칸 (#326).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_care_link.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
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

({FamilyRepository repo, List<http.Request> posts}) _fixture({bool hasGroup = true}) {
  final posts = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return hasGroup
            ? _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []})
            : _json({'error': {'code': 'NOT_FOUND'}}, status: 404);
      }
      if (request.method == 'POST') {
        posts.add(request);
        return _json({
          'id': 99,
          'dogId': null,
          'groupId': 3,
          'type': 'walk',
          'doneBy': {'userId': 11, 'nickname': '나'},
          'occurredAt': '2026-09-07T09:05:00',
          'memo': null,
        }, status: 201);
      }
      return _json(const []);
    }),
    baseUrl: _base,
    store: _Tokens(),
  );
  return (repo: FamilyRepository(baseUrl: _base, client: client), posts: posts);
}

void main() {
  setUp(() => kServerCareRev.value = 0);

  test('가족이 있으면 walk 케어 로그를 하나 남기고 카드를 다시 읽게 한다', () async {
    final f = _fixture();

    final ok = await WalkCareLink(repository: f.repo).recordWalk();

    expect(ok, isTrue);
    expect(f.posts, hasLength(1));
    expect(f.posts.single.url.path, '/api/groups/3/care-logs');
    expect(jsonDecode(f.posts.single.body)['type'], 'walk');
    expect(kServerCareRev.value, 1, reason: '홈 케어 카드가 다시 읽어야 "아직" 이 사라진다');
  });

  test('가족이 없으면 아무것도 하지 않고 false — 오류가 아니다', () async {
    final f = _fixture(hasGroup: false);

    final ok = await WalkCareLink(repository: f.repo).recordWalk();

    expect(ok, isFalse);
    expect(f.posts, isEmpty);
    expect(kServerCareRev.value, 0);
  });
}

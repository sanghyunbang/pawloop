// 글 목록의 장소 필터 — 이슈 #723 (조각 2). `feed(contentId:)` 가 `?contentId=` 를 싣는다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';

const _base = 'https://api.example.test';

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
  late List<http.Request> requests;
  late CommunityRepository repo;

  setUp(() {
    requests = [];
    repo = CommunityRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'items': const [], 'nextCursor': null, 'hasMore': false}), 200,
              headers: const {'content-type': 'application/json; charset=utf-8'});
        }),
        baseUrl: _base,
        store: _NoTokens(),
      ),
    );
  });

  test('contentId 를 주면 그대로 쿼리에 싣는다 — 다른 필터와 함께', () async {
    await repo.feed(contentId: '2745594', board: CommunityBoard.petPlace, limit: 30);
    final q = requests.single.url.queryParameters;
    expect(q['contentId'], '2745594');
    expect(q['board'], 'pet_place');
    expect(q['limit'], '30');
  });

  test('안 주거나 비어 있으면 쿼리에 없다 — 빈 값을 보내 서버에 해석을 떠넘기지 않는다', () async {
    await repo.feed();
    await repo.feed(contentId: '');
    for (final r in requests) {
      expect(r.url.queryParameters.containsKey('contentId'), isFalse, reason: r.url.toString());
    }
  });
}

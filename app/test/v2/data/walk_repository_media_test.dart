// 산책 저장 요청에 mediaIds 가 실린다 — 이슈 #450. 비어 있으면 키 자체가 없다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'token';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _walkJson = '{"id":1,"dogId":9,"dogIds":[9],"clientWalkId":"abcdefgh","startedAt":"2026-09-14T07:00:00Z",'
    '"distanceM":1200,"durationS":1800,"media":[{"id":31,"kind":"image","url":"https://cdn/a.jpg"}]}';

WalkRepository _repo(List<Map<String, dynamic>> bodies) => WalkRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(_walkJson, 201, headers: {'content-type': 'application/json'});
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

void main() {
  test('mediaIds 가 있으면 본문에 그대로 싣고, 응답의 media 를 읽는다', () async {
    final bodies = <Map<String, dynamic>>[];

    final walk = await _repo(bodies).saveWalk(
      dogId: 9,
      clientWalkId: 'abcdefgh',
      startedAt: DateTime(2026, 9, 14, 7),
      distanceM: 1200,
      durationS: 1800,
      mediaIds: const [31, 32],
    );

    expect(bodies.single['mediaIds'], [31, 32]);
    expect(walk.media.single.url, 'https://cdn/a.jpg');
  });

  test('사진이 없으면 mediaIds 키를 안 보낸다 — 서버가 "안 보냄" 과 "빈 배열" 을 같게 보지만 굳이 보내지 않는다', () async {
    final bodies = <Map<String, dynamic>>[];

    await _repo(bodies).saveWalk(
      dogId: 9,
      clientWalkId: 'abcdefgh',
      startedAt: DateTime(2026, 9, 14, 7),
      distanceM: 1200,
      durationS: 1800,
    );

    expect(bodies.single.containsKey('mediaIds'), isFalse);
  });
}

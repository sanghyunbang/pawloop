// 글에 붙은 코스 — 보내는 모양 · 읽는 모양 · 붙이기와 떼기 (#339).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';

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

({CommunityRepository repo, List<http.Request> seen}) _repo(
  http.Response Function(http.Request request) answer,
) {
  final seen = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      return answer(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CommunityRepository(baseUrl: _base, client: client), seen: seen);
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 계약의 `Post` 그대로 — 서버가 주는 키다.
Map<String, Object?> _postJson({Object? course}) => {
      'id': 11,
      'author': {'userId': 3, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'loc': null,
      'contentId': null,
      'title': '이 길 좋아요',
      'body': '그늘이 많아요',
      'course': course,
      'commentCount': 0,
      'reactions': {'cute': 0, 'helpful': 0, 'same': 0, 'mine': []},
      'createdAt': '2026-09-07T04:00:00Z',
      'hiddenByBlock': false,
    };

Map<String, Object?> _courseJson() => {
      'id': 5,
      'name': '서울숲 한 바퀴',
      'distanceM': 400,
      'path': [
        [127.041, 37.5445],
        [127.045, 37.5449],
      ],
    };

void main() {
  setUp(() => LocationUploadPolicy.setForTest(true));
  tearDown(LocationUploadPolicy.resetForTest);

  group('보내는 모양', () {
    test('코스를 고르면 courseId 만 보낸다 — 선은 서버가 갖고 있다', () async {
      final r = _repo((_) => _json(_postJson(course: _courseJson()), status: 201));

      await r.repo.createPost(
        board: CommunityBoard.walkReview,
        title: '이 길 좋아요',
        body: '그늘이 많아요',
        courseId: 5,
      );

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body['courseId'], 5);
      expect(body.containsKey('path'), isFalse);
    });

    test('코스를 안 고르면 키 자체를 안 보낸다', () async {
      final r = _repo((_) => _json(_postJson(), status: 201));

      await r.repo.createPost(board: CommunityBoard.free, title: '제목', body: '본문');

      final body = jsonDecode(r.seen.single.body) as Map<String, dynamic>;
      expect(body.containsKey('courseId'), isFalse);
    });
  });

  group('읽는 모양', () {
    test('붙은 코스를 읽는다 — 선은 카드에 그릴 만큼만 온다', () async {
      final r = _repo((_) => _json(_postJson(course: _courseJson()), status: 201));

      final post = await r.repo.createPost(
        board: CommunityBoard.walkReview,
        title: '이 길 좋아요',
        body: '본문',
        courseId: 5,
      );

      expect(post.course?.name, '서울숲 한 바퀴');
      expect(post.course?.km, closeTo(0.4, 0.001));
      expect(post.course?.drawable, isTrue);
    });

    test('안 붙었거나 비공개로 되돌렸으면 null — 셋을 구분하지 않는다', () async {
      final r = _repo((_) => _json(_postJson(), status: 201));

      final post = await r.repo.createPost(
        board: CommunityBoard.walkReview,
        title: '제목',
        body: '본문',
      );

      expect(post.course, isNull);
    });

    test('모양이 깨진 코스는 없는 것으로 둔다 — 글까지 잃지 않는다', () async {
      final r = _repo((_) => _json(_postJson(course: {'name': '이름만'}), status: 201));

      final post = await r.repo.createPost(
        board: CommunityBoard.walkReview,
        title: '제목',
        body: '본문',
      );

      expect(post.course, isNull);
    });
  });

  group('붙이기와 떼기', () {
    test('붙이기는 PUT · 떼기는 DELETE — 같은 경로다', () async {
      final r = _repo((request) => _json(
            _postJson(course: request.method == 'PUT' ? _courseJson() : null),
          ));

      final attached = await r.repo.attachCourse(11, 5);
      final detached = await r.repo.detachCourse(11);

      expect(r.seen[0].method, 'PUT');
      expect(r.seen[0].url.path, '/api/community/posts/11/course');
      expect(jsonDecode(r.seen[0].body)['courseId'], 5);
      expect(attached.course?.id, 5);

      expect(r.seen[1].method, 'DELETE');
      expect(r.seen[1].url.path, '/api/community/posts/11/course');
      expect(detached.course, isNull);
    });
  });
}

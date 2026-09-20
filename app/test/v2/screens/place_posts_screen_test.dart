// 이 장소의 글 — 이슈 #723 (조각 2).
//
// 진짜 `CommunityRepository` 에 `MockClient`. 여기서 재는 것 넷.
//   - 서버에 **그 장소의 contentId** 로 묻는다(?contentId=)
//   - 사진 있는 글은 사진 벽, 글만 있는 글은 한 줄 — 아이 사진첩과 같은 모양
//   - 글이 없으면 "없어요" 로 끝내지 않고 **첫 글의 문**('이 장소로 글쓰기')을 연다
//   - 토큰이 없어도 부른다 — 글은 공개다. 아이 사진첩의 토큰 문을 그대로 베끼면 게스트에게 벽이 된다
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/place_posts_screen.dart';

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

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _post({required int id, required String title, bool withMedia = false}) => {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'title': title,
      'body': '본문',
      'contentId': '2745594',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': withMedia
          ? [
              {
                'id': id,
                'kind': 'image',
                'url': 'https://cdn.example.test/posts/$id/1.jpg',
                'posterUrl': null,
                'width': 1600,
                'height': 1200,
                'durationMs': null,
              }
            ]
          : const [],
      'bookmarked': false,
      'dog': null,
    };

class _Fixture {
  final CommunityRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);
}

_Fixture _fixture({List<Map<String, Object?>> feed = const []}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      return _json({'items': feed, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _NoTokens(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('그 장소의 contentId 로 묻고, 사진 벽과 글 줄로 그린다', (tester) async {
    final f = _fixture(feed: [
      _post(id: 1, title: '마당 사진', withMedia: true),
      _post(id: 2, title: '그늘 벤치 후기'),
    ]);
    await tester.pumpWidget(_host(PlacePostsScreen(contentId: '2745594', title: '성수연방', repository: f.repo)));
    await tester.pumpAndSettle();

    expect(f.requests.single.url.path, '/api/community/posts');
    expect(f.requests.single.url.queryParameters['contentId'], '2745594',
        reason: '서버가 좁혀 준다 — 전체를 받아 앱에서 거르면 첫 장에 없는 글은 영영 안 보인다');
    expect(find.text('성수연방의 글'), findsOneWidget);
    expect(find.byKey(const Key('place-posts-list')), findsOneWidget);
    expect(find.byKey(const Key('place-posts-row-2')), findsOneWidget, reason: '글만 있는 글은 한 줄');
    expect(find.byKey(const Key('place-posts-row-1')), findsNothing, reason: '사진 있는 글은 사진 벽으로 간다');
  });

  testWidgets('글이 없으면 첫 글의 문을 연다 — "이 장소로 글쓰기"', (tester) async {
    final f = _fixture();
    await tester.pumpWidget(_host(PlacePostsScreen(contentId: '2745594', title: '성수연방', repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('place-posts-empty')), findsOneWidget);
    expect(find.text('아직 이 장소의 글이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('place-posts-write-first')), findsOneWidget);
    expect(find.text('이 장소로 글쓰기'), findsOneWidget);
  });

  testWidgets('토큰이 없어도(게스트) 서버를 부른다 — 글은 공개다', (tester) async {
    // 위 두 검사도 토큰 없는 저장소로 돈다. 여기서는 그 사실을 이름으로 못 박는다 — 아이 사진첩처럼
    // `AuthState.hasNoToken` 문을 두면 첫 요청이 아예 안 나가서 `requests` 가 빈다.
    final f = _fixture(feed: [_post(id: 3, title: '게스트도 본다')]);
    await tester.pumpWidget(_host(PlacePostsScreen(contentId: '2745594', title: '성수연방', repository: f.repo)));
    await tester.pumpAndSettle();

    expect(f.requests, hasLength(1));
    expect(find.byKey(const Key('place-posts-row-3')), findsOneWidget);
  });
}

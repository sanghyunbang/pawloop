// 저장 — "내 사진첩" (이슈 #451 4번).
//
// 카드·상세의 책갈피가 켜고 끈다(둘 다 멱등한 POST·DELETE, 응답의 상태를 그린다) · 저장한 글
// 화면은 저장한 순의 사진 벽 + 글만 있는 글 한 줄씩 · 내 정보 메뉴의 "저장한 글" 행.
//
// `community_feed_like_test.dart` 와 같은 방식 — 진짜 `CommunityRepository` 에 `MockClient`.
// 응답에는 **계약의 키만** 넣는다(`bookmarked` · `BookmarkState.bookmarked`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';
import 'package:heat_trip_flutter/v2/screens/saved_posts_screen.dart';

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

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _media(int id) => {
      'id': id,
      'kind': 'image',
      'url': 'https://cdn.example.test/posts/7/$id.jpg',
      'posterUrl': null,
      'width': 1600,
      'height': 1200,
      'durationMs': null,
    };

Map<String, Object?> _post({
  int id = 12,
  bool bookmarked = false,
  List<String>? mine = const [],
  bool withMedia = true,
  String title = '서울숲 아침 산책 코스 추천',
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'title': title,
      'body': '본문',
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': withMedia ? [_media(id)] : const [],
      'bookmarked': bookmarked,
    };

class _Fixture {
  final CommunityRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);

  List<String> get bookmarkCalls => [
        for (final r in requests)
          if (r.url.path.endsWith('/bookmark')) '${r.method} ${r.url.path}',
      ];
}

/// [feed] 는 글 목록, [saved] 는 저장한 글 목록. 저장·빼기는 계약대로 `{bookmarked}` 만 준다.
_Fixture _fixture({
  List<Map<String, Object?>> feed = const [],
  List<Map<String, Object?>> saved = const [],
  http.Response Function(http.Request request)? onBookmark,
  http.Response Function(http.Request request)? onSaved,
}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/bookmark')) {
        if (onBookmark != null) return onBookmark(request);
        return _json({'bookmarked': request.method == 'POST'});
      }
      if (path == '/api/community/bookmarks') {
        if (onSaved != null) return onSaved(request);
        return _json({'items': saved, 'nextCursor': null, 'hasMore': false});
      }
      if (path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      if (RegExp(r'^/api/community/posts/\d+$').hasMatch(path)) {
        final id = int.parse(path.split('/').last);
        return _json([...feed, ...saved].firstWhere((p) => p['id'] == id));
      }
      return _json({'items': feed, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

Widget _host(Widget child) => MaterialApp(home: child);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('저장소 — 계약의 키', () {
    test('저장·빼기는 멱등한 POST·DELETE 둘이고 응답의 상태를 돌려준다', () async {
      final f = _fixture();

      expect(await f.repo.bookmark(12), isTrue);
      expect(await f.repo.unbookmark(12), isFalse);
      expect(f.bookmarkCalls, [
        'POST /api/community/posts/12/bookmark',
        'DELETE /api/community/posts/12/bookmark',
      ]);
    });

    test('bookmarked 가 없는 응답은 실패다 — false 로 그리면 저장이 안 된 것처럼 보인다', () async {
      final f = _fixture(onBookmark: (_) => _json({'ok': true}));

      expect(() => f.repo.bookmark(12), throwsA(isA<CommunityFailure>()));
    });

    test('저장한 글 목록은 /api/community/bookmarks 이고 items 봉투다 · Post.bookmarked 를 읽는다', () async {
      final f = _fixture(saved: [_post(id: 3, bookmarked: true)]);

      final page = await f.repo.bookmarks(limit: 20);

      expect(f.requests.single.url.path, '/api/community/bookmarks');
      expect(f.requests.single.url.queryParameters['limit'], '20');
      expect(page.items.single.bookmarked, isTrue);
      expect(CommunityPost.tryParse(_post(id: 4))!.bookmarked, isFalse);
      expect(CommunityPost.tryParse({..._post(id: 5)}..remove('bookmarked'))!.bookmarked, isFalse,
          reason: '키가 없으면(옛 서버) 안 저장한 것으로 — 게스트도 false 다');
    });
  });

  group('카드', () {
    testWidgets('책갈피를 누르면 저장(POST) — 채운 아이콘, 카드는 안 열린다. 다시 누르면 뺀다(DELETE)', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [_post()]);
      await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('bookmark-12'));
      expect(find.descendant(of: button, matching: find.byIcon(Icons.bookmark_border_rounded)), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(f.bookmarkCalls, ['POST /api/community/posts/12/bookmark']);
      expect(find.descendant(of: button, matching: find.byIcon(Icons.bookmark_rounded)), findsOneWidget);
      expect(find.byType(PostDetailScreen), findsNothing, reason: '안쪽 탭이 이긴다');
      expect(find.textContaining('저장했어요'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(f.bookmarkCalls.last, 'DELETE /api/community/posts/12/bookmark');
      expect(find.descendant(of: button, matching: find.byIcon(Icons.bookmark_border_rounded)), findsOneWidget);
    });

    testWidgets('서버가 준 상태를 그린다 — 저장했다고 답했는데 false 면 꺼진 채다', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [_post()], onBookmark: (_) => _json({'bookmarked': false}));
      await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bookmark-12')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsNothing, reason: '로컬에서 뒤집으면 서버와 어긋난다');
    });

    testWidgets('게스트(mine 이 null)는 서버를 안 부르고 로그인 안내가 뜬다', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [_post(mine: null)]);
      await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bookmark-12')));
      await tester.pumpAndSettle();

      expect(f.bookmarkCalls, isEmpty);
      expect(find.text('로그인하면 글을 저장할 수 있어요'), findsOneWidget);
    });

    testWidgets('서버가 거절하면 아이콘은 그대로고 안내가 뜬다', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [_post()], onBookmark: (_) => _json({'error': 'down'}, status: 500));
      await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bookmark-12')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('상세', () {
    testWidgets('머리말의 책갈피가 켜고 끈다 — 돌아갈 때 목록이 다시 읽도록 바뀜을 남긴다', (tester) async {
      _phone(tester);
      final json = _post(bookmarked: true);
      final f = _fixture(feed: [json]);
      await tester.pumpWidget(_host(PostDetailScreen(post: CommunityPost.tryParse(json)!, repository: f.repo)));
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('detail-bookmark'));
      expect(find.descendant(of: button, matching: find.byIcon(Icons.bookmark_rounded)), findsOneWidget,
          reason: '저장해 둔 글로 들어왔다');

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(f.bookmarkCalls, ['DELETE /api/community/posts/12/bookmark']);
      expect(find.descendant(of: button, matching: find.byIcon(Icons.bookmark_border_rounded)), findsOneWidget);
      expect(find.textContaining('저장을 뺐어요'), findsOneWidget);
    });

    testWidgets('게스트는 로그인 안내를 받고 서버를 안 부른다', (tester) async {
      _phone(tester);
      final json = _post(mine: null);
      final f = _fixture(feed: [json]);
      await tester.pumpWidget(_host(PostDetailScreen(post: CommunityPost.tryParse(json)!, repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('detail-bookmark')));
      await tester.pumpAndSettle();

      expect(f.bookmarkCalls, isEmpty);
      expect(find.textContaining('로그인하면'), findsWidgets);
    });
  });

  group('저장한 글 화면', () {
    setUp(() {
      AuthState.resetForTest();
      AuthState.status.value = AuthStatus.authenticated;
    });
    tearDown(AuthState.resetForTest);

    testWidgets('게스트면 서버를 안 부르고 로그인 안내다 — 누구의 것도 아닌 목록은 없다', (tester) async {
      _phone(tester);
      AuthState.status.value = AuthStatus.unauthenticated;
      final f = _fixture(saved: [_post(id: 31, bookmarked: true)]);
      await tester.pumpWidget(_host(SavedPostsScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      expect(f.requests, isEmpty);
      expect(find.textContaining('로그인하면'), findsOneWidget);
      expect(find.byKey(const Key('post-photo-wall')), findsNothing);
    });

    testWidgets('사진 있는 글은 벽으로, 글만 있는 글은 한 줄로 — 저장한 순 그대로', (tester) async {
      _phone(tester);
      final f = _fixture(saved: [
        _post(id: 31, bookmarked: true, title: '사진 글'),
        _post(id: 32, bookmarked: true, withMedia: false, title: '글만 있는 글'),
        _post(id: 33, bookmarked: true, title: '또 사진 글'),
      ]);
      await tester.pumpWidget(_host(SavedPostsScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      expect(find.text('저장한 글'), findsOneWidget);
      expect(find.byKey(const Key('post-photo-wall')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-31')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-33')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-32')), findsNothing, reason: '글만 있는 글은 벽에 없다');
      expect(find.byKey(const Key('saved-row-32')), findsOneWidget);
      expect(find.byKey(const Key('photo-like-31')), findsNothing, reason: '사진첩에는 하트 알약이 없다 — 구경하는 곳');
      expect(tester.takeException(), isNull);
    });

    testWidgets('타일을 누르면 상세로, 거기서 저장을 빼고 돌아오면 목록이 다시 읽힌다', (tester) async {
      _phone(tester);
      var savedCalls = 0;
      final f = _fixture(
        saved: [_post(id: 31, bookmarked: true)],
        onSaved: (_) {
          savedCalls++;
          return _json({
            'items': savedCalls == 1 ? [_post(id: 31, bookmarked: true)] : const [],
            'nextCursor': null,
            'hasMore': false,
          });
        },
      );
      await tester.pumpWidget(_host(SavedPostsScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('photo-tile-31')));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail-bookmark')));
      await tester.pumpAndSettle();
      expect(f.bookmarkCalls, ['DELETE /api/community/posts/31/bookmark']);

      // 상세의 뒤로 가기는 머티리얼 앱바가 아니라 화면이 그린 화살표다 — pageBack 이 못 찾는다.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(savedCalls, 2, reason: '바뀌었다고 알려 왔으니 다시 읽는다');
      expect(find.byKey(const Key('saved-empty')), findsOneWidget, reason: '뺀 글은 사라졌다');
    });

    testWidgets('하나도 없으면 그 말을 하고, 못 불러오면 다시 시도가 있다', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(SavedPostsScreen(repository: _fixture().repo)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saved-empty')), findsOneWidget);
      expect(find.text('저장한 글이 없어요'), findsOneWidget);

      // 연결이 끊긴 것(network)만 다시 시도할 수 있다 — 500 처럼 서버가 거절한 것은 눌러도 같다.
      var calls = 0;
      final failing = _fixture(onSaved: (_) {
        calls++;
        if (calls == 1) throw http.ClientException('down');
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      });
      // 키를 달아 새 State 로 — 같은 자리의 같은 위젯이면 State 가 재사용돼 initState 가 다시 안 돈다.
      await tester.pumpWidget(_host(SavedPostsScreen(key: const Key('second'), repository: failing.repo)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saved-retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('saved-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saved-empty')), findsOneWidget);
    });

    testWidgets('더 보기가 다음 장을 커서로 잇는다', (tester) async {
      _phone(tester);
      final f = _fixture(onSaved: (request) {
        final cursor = request.url.queryParameters['cursor'];
        return _json({
          'items': [_post(id: cursor == null ? 41 : 42, bookmarked: true, withMedia: false, title: cursor == null ? '첫 장' : '둘째 장')],
          'nextCursor': cursor == null ? 'c1' : null,
          'hasMore': cursor == null,
        });
      });
      await tester.pumpWidget(_host(SavedPostsScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('saved-more')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('saved-row-41')), findsOneWidget);
      expect(find.byKey(const Key('saved-row-42')), findsOneWidget);
      expect(f.requests.last.url.queryParameters['cursor'], 'c1');
      expect(find.byKey(const Key('saved-more')), findsNothing);
    });
  });
}

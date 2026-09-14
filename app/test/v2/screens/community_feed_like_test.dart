// 좋아요 — 이슈 #451 (4번).
//
// 카드의 사진을 두 번 탭하면 귀여워요(하트가 튄다, Instagram) · 액션 줄의 반응은 누르면 켜고 끈다 ·
// 벽 타일의 하트 알약. 상세와 같은 규칙 — 낙관적 갱신 없이 서버 응답의 집계를 그린다.
//
// `community_feed_media_test.dart` 와 같은 방식 — 진짜 `CommunityRepository` 에 `MockClient`.
import 'dart:convert';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';

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

/// `mine` 이 null 이면 게스트 응답이다.
Map<String, Object?> _post({int id = 12, List<String>? mine = const [], bool withMedia = true}) => {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'free',
      'title': '글 $id',
      'body': '본문',
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': withMedia ? [_media(id)] : const [],
    };

class _Fixture {
  final CommunityRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);

  List<http.Request> get reactionCalls =>
      requests.where((r) => r.url.path.contains('/reactions/')).toList();
}

_Fixture _fixture(List<Map<String, Object?>> items,
    {http.Response Function(http.Request request)? onReaction}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      if (request.url.path.contains('/reactions/')) {
        if (onReaction != null) return onReaction(request);
        // 서버의 집계 — 로컬에서 ±1 한 것과 **다른 수**를 준다(켜면 5, 끄면 1). 남이 같은 시간에
        // 누른 것이 섞인 값이다 — 로컬에서 세면 4·2 가 그려지고 그건 거짓이다.
        final mine = request.method == 'DELETE' ? const <String>[] : const ['cute'];
        return _json({'help': 7, 'cute': request.method == 'DELETE' ? 1 : 5, 'empathy': 2, 'mine': mine});
      }
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      if (RegExp(r'^/api/community/posts/\d+$').hasMatch(request.url.path)) {
        return _json(items.first);
      }
      return _json({'items': items, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

Widget _host(Widget child) => MaterialApp(home: child);

final _strip = find.byKey(const Key('post-media-strip'));
final _burst = find.byKey(const Key('like-burst'));

/// 카드 액션 줄의 귀여워요 수 — 공감도 2 라서 글자만으로 찾으면 둘이 잡힌다.
Finder _cuteCount(String count) =>
    find.descendant(of: find.byKey(const Key('reaction-cute-12')), matching: find.text(count));

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 두 번 탭 — 첫 탭에서 최소 간격(40ms)이 지나야 둘째 탭이 두 번 탭으로 묶인다.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pump();
}

Future<_Fixture> _pump(WidgetTester tester, List<Map<String, Object?>> items,
    {http.Response Function(http.Request request)? onReaction}) async {
  _phone(tester);
  final f = _fixture(items, onReaction: onReaction);
  await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
  await tester.pumpAndSettle();
  return f;
}

void main() {
  testWidgets('사진을 두 번 탭하면 귀여워요 — 하트가 바로 튀고, 집계는 서버 응답으로 그린다', (tester) async {
    final f = await _pump(tester, [_post()]);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget, reason: '아직 안 눌렀다');

    await _doubleTap(tester, _strip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(_burst, findsOneWidget, reason: '손가락에 대한 대답 — 응답을 기다리지 않는다');
    final call = f.reactionCalls.single;
    expect(call.method, 'POST');
    expect(call.url.path, '/api/community/posts/12/reactions/cute');

    await tester.pumpAndSettle();
    expect(_burst, findsNothing, reason: '튀고 나면 사라진다');
    expect(_cuteCount('5'), findsOneWidget, reason: '서버가 준 5 — 로컬에서 +1 하면 4 가 그려지고 남이 누른 것이 안 보인다');
    expect(_cuteCount('4'), findsNothing);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget, reason: '채운 하트');
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byKey(const Key('post-media-viewer')), findsNothing, reason: '두 번 탭은 전체 보기를 열지 않는다');
  });

  testWidgets('이미 눌렀으면 두 번 탭은 떼지 않는다 — 하트만 튄다 (Instagram)', (tester) async {
    final f = await _pump(tester, [_post(mine: const ['cute'])]);

    await _doubleTap(tester, _strip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(_burst, findsOneWidget);
    expect(f.reactionCalls, isEmpty, reason: 'DELETE 를 보내면 실수로 두 번 탭한 사람의 좋아요가 사라진다');
    await tester.pumpAndSettle();
    expect(_cuteCount('3'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('액션 줄의 반응을 누르면 켜고 끈다 — 카드가 열리지 않는다', (tester) async {
    final f = await _pump(tester, [_post(mine: const ['cute'])]);

    await tester.tap(find.byKey(const Key('reaction-cute-12')));
    await tester.pumpAndSettle();

    final call = f.reactionCalls.single;
    expect(call.method, 'DELETE', reason: '눌러 둔 것을 누르면 뗀다');
    expect(call.url.path, '/api/community/posts/12/reactions/cute');
    expect(_cuteCount('1'), findsOneWidget, reason: '서버가 준 1 — 로컬에서 -1 하면 2 다');
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byType(PostDetailScreen), findsNothing, reason: '안쪽 탭이 이긴다 — 카드 열기가 가로채지 않는다');
    expect(_burst, findsNothing, reason: '하트는 두 번 탭에만 튄다');

    await tester.tap(find.byKey(const Key('reaction-help-12')));
    await tester.pumpAndSettle();
    expect(f.reactionCalls.last.method, 'POST');
    expect(f.reactionCalls.last.url.path, '/api/community/posts/12/reactions/help');
  });

  testWidgets('게스트(mine 이 null)는 두 번 탭해도 서버를 안 부르고 로그인 안내가 뜬다', (tester) async {
    final f = await _pump(tester, [_post(mine: null)]);

    await _doubleTap(tester, _strip);
    await tester.pump(const Duration(milliseconds: 100));

    expect(f.reactionCalls, isEmpty);
    expect(_burst, findsNothing, reason: '누를 수 없는데 하트가 튀면 눌린 줄 안다');
    expect(find.text('로그인하면 반응을 남길 수 있어요'), findsOneWidget);
  });

  testWidgets('서버가 거절하면 집계는 그대로고 안내가 뜬다 — 되돌릴 자리가 없다', (tester) async {
    final f = await _pump(tester, [_post()],
        onReaction: (_) => _json({'error': 'down'}, status: 500));

    await _doubleTap(tester, _strip);
    await tester.pumpAndSettle();

    expect(f.reactionCalls.single.method, 'POST');
    expect(_cuteCount('3'), findsOneWidget, reason: '낙관적으로 4 를 그렸다면 실패 뒤에 거짓이 남는다');
    expect(_cuteCount('4'), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('한 번 탭은 그대로 전체 보기다 — 두 번 탭 판정(300ms)만큼 늦게', (tester) async {
    await _pump(tester, [_post()]);

    await tester.tap(_strip);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-viewer')), findsOneWidget);
    expect(_burst, findsNothing);
  });

  group('사진 벽', () {
    testWidgets('타일의 하트 알약 — 수가 보이고, 누르면 귀여워요를 켠다. 타일 열기가 가로채지 않는다', (tester) async {
      final f = await _pump(tester, [_post(id: 12), _post(id: 13, mine: const ['cute'])]);
      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();

      final pill = find.byKey(const Key('photo-like-12'));
      expect(pill, findsOneWidget);
      expect(find.descendant(of: pill, matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: pill, matching: find.byIcon(Icons.favorite_border_rounded)), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('photo-like-13')), matching: find.byIcon(Icons.favorite_rounded)),
          findsOneWidget,
          reason: '내가 누른 글은 채운 하트');

      await tester.tap(pill);
      await tester.pumpAndSettle();

      expect(f.reactionCalls.single.method, 'POST');
      expect(f.reactionCalls.single.url.path, '/api/community/posts/12/reactions/cute');
      expect(find.descendant(of: pill, matching: find.text('5')), findsOneWidget, reason: '서버가 준 값');
      expect(find.descendant(of: pill, matching: find.byIcon(Icons.favorite_rounded)), findsOneWidget);
      expect(find.byType(PostDetailScreen), findsNothing);
    });

    testWidgets('벽의 타일은 한 번 탭에 바로 열린다 — 두 번 탭 인식기가 없다', (tester) async {
      await _pump(tester, [_post(id: 12)]);
      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('photo-tile-12')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(PostDetailScreen), findsOneWidget, reason: '300ms 를 기다리지 않는다 — 벽은 구경하는 곳이다');
    });
  });
}

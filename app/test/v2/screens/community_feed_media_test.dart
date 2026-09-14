// 카드와 상세가 글에 붙은 사진·영상을 그린다 (#429).
//
// `community_feed_test.dart` 와 같은 방식 — 진짜 `CommunityRepository` 에 `MockClient`.
// 그림 자체는 테스트에서 안 내려온다(네트워크 없음) — 자리·개수·`+N`·전체 보기를 본다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';
import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_strip.dart';

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

Map<String, Object?> _media(int id, {String kind = 'image', int? width = 1600, int? height = 1200}) => {
      'id': id,
      'kind': kind,
      'url': 'https://cdn.example.test/posts/7/$id.${kind == 'video' ? 'mp4' : 'jpg'}',
      'posterUrl': kind == 'video' ? 'https://cdn.example.test/posts/7/$id.jpg' : null,
      'width': width,
      'height': height,
      'durationMs': kind == 'video' ? 8000 : null,
    };

Map<String, Object?> _post({int id = 12, List<Map<String, Object?>> media = const []}) => {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'loc': '서울숲',
      'contentId': '126508',
      'title': '서울숲 아침 산책 코스 추천',
      'body': '이른 아침엔 사람이 적어서 대형견도 편해요.',
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': media,
    };

CommunityRepository _repo(List<Map<String, Object?>> items, {Map<String, Object?>? detail}) {
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.method == 'GET' && RegExp(r'^/api/community/posts/\d+$').hasMatch(request.url.path)) {
        return _json(detail ?? items.first);
      }
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      return _json({'items': items, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return CommunityRepository(baseUrl: _base, client: client);
}

Widget _host(Widget child) => MaterialApp(home: child);

final _strip = find.byKey(const Key('post-media-strip'));

/// 폰 폭에 긴 표면 — 2×2 격자가 카드 폭만큼 높아서 기본 표면(800×600)에서는 카드 하나가
/// 화면을 넘고, 넘은 칸은 누를 수 없다.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('사진이 한 장이면 카드 폭으로 크게 — 서버가 준 크기로 자리를 미리 잡는다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [_media(1, width: 1600, height: 1200)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    final aspect = tester.widget<AspectRatio>(find.descendant(of: _strip, matching: find.byType(AspectRatio)));
    expect(aspect.aspectRatio, closeTo(4 / 3, 1e-9), reason: '그림이 오기 전에 자리가 잡혀 카드가 뛰지 않는다');
    expect(find.descendant(of: _strip, matching: find.byType(Image)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진이 없으면 자리도 없다', (tester) async {
    _phone(tester);
    final repo = _repo([_post()]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(_strip, findsNothing);
  });

  testWidgets('넷을 넘으면 넷째 칸에 +N 이고, 그림은 넷만 받는다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [for (var i = 1; i <= 6; i++) _media(i)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('+2'), findsOneWidget);
    expect(find.descendant(of: _strip, matching: find.byType(Image)), findsNWidgets(4),
        reason: '목록 한 장에 URL 여섯이 와도 그림은 넷만 내려받는다');
  });

  testWidgets('영상은 썸네일 위에 재생 표시다 — 피드에서 자동재생하지 않는다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [_media(1, kind: 'video', width: 1280, height: 720)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    final image = tester.widget<Image>(find.descendant(of: _strip, matching: find.byType(Image)));
    expect((image.image as NetworkImage).url, endsWith('/1.jpg'), reason: '그리는 것은 영상이 아니라 썸네일이다');
  });

  testWidgets('+N 을 누르면 전체 보기가 그 자리에서 열린다 — 카드가 아니라 사진이 먼저 받는다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [for (var i = 1; i <= 6; i++) _media(i)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+2'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-viewer')), findsOneWidget);
    expect(find.text('4 / 6'), findsOneWidget, reason: '넷째 칸을 눌렀으니 넷째부터');
    expect(find.byType(PostDetailScreen), findsNothing, reason: '카드의 상세 열기가 가로채지 않는다');

    await tester.tap(find.byKey(const Key('post-media-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-media-viewer')), findsNothing);
  });

  testWidgets('상세에도 같은 격자가 뜬다', (tester) async {
    _phone(tester);
    final json = _post(media: [_media(1), _media(2)]);
    final repo = _repo([json], detail: json);
    await tester.pumpWidget(_host(PostDetailScreen(post: CommunityPost.tryParse(json)!, repository: repo)));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(find.descendant(of: _strip, matching: find.byType(Image)), findsNWidgets(2));
  });

  testWidgets('좁은 화면·큰 글씨에서도 격자가 넘치지 않는다 — 한 장·둘·여섯', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final media in [
      [_media(1, width: 100, height: 1000)],
      [_media(1), _media(2)],
      [for (var i = 1; i <= 6; i++) _media(i)],
    ]) {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        // 카드와 같은 좌우 여백 — 격자가 받는 폭이 같다.
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: PostMediaStrip(media: PostMedia.parseList(media)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(_strip, findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${media.length}장');
    }
  });
  // ── 사진 벽 (#451 1번) — 격자 보기는 사진·영상이 있는 글만 두 열로 깐다
  group('사진 벽', () {
    testWidgets('격자로 바꾸면 사진 있는 글만 타일이고 글만 있는 글은 없다 — 카드는 안 그린다', (tester) async {
      _phone(tester);
      final repo = _repo([
        _post(id: 12, media: [_media(1, width: 1080, height: 1350)]),
        _post(id: 13),
        _post(id: 14, media: [_media(2, kind: 'video', width: 1280, height: 720), _media(3)]),
      ]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('post-photo-wall')), findsNothing, reason: '기본은 카드 보기다');

      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('post-photo-wall')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-12')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-14')), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-13')), findsNothing, reason: '사진 없는 글은 벽에 없다');
      expect(_strip, findsNothing, reason: '격자에서는 카드를 안 그린다');
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget, reason: '영상은 재생 표시');
      expect(find.text('+1'), findsOneWidget, reason: '사진이 둘이면 +1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('사진 있는 글이 하나도 없으면 벽 대신 그 말을 한다', (tester) async {
      _phone(tester);
      final repo = _repo([_post(id: 12), _post(id: 13)]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feed-photo-empty')), findsOneWidget);
      expect(find.byKey(const Key('post-photo-wall')), findsNothing);
    });

    testWidgets('타일을 누르면 글 상세로 간다', (tester) async {
      _phone(tester);
      final repo = _repo([_post(id: 12, media: [_media(1)])]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('photo-tile-12')));
      await tester.pumpAndSettle();

      expect(find.byType(PostDetailScreen), findsOneWidget);
    });
  });
  // ── 사진이 먼저 (#451 2번)
  testWidgets('사진 있는 글은 카드에서 사진이 작성자·제목보다 위다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [_media(1, width: 1600, height: 1200)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    final strip = tester.getTopLeft(_strip);
    final author = tester.getTopLeft(find.text('보리아빠'));
    final title = tester.getTopLeft(find.text('서울숲 아침 산책 코스 추천'));
    expect(strip.dy, lessThan(author.dy), reason: '벽에서처럼 카드에서도 사진이 주인공이다');
    expect(strip.dy, lessThan(title.dy));
  });
  testWidgets('홈이 사진 벽을 부탁하면 격자로 열리고, 부탁은 한 번짜리다 (#451 6번)', (tester) async {
    _phone(tester);
    addTearDown(() => RootTab.communityView.value = 'card');
    RootTab.communityView.value = 'grid';
    final repo = _repo([_post(id: 12, media: [_media(1)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-photo-wall')), findsOneWidget, reason: '홈의 더 보기가 부탁한 대로 격자');
    expect(RootTab.communityView.value, 'card', reason: '읽은 뒤 되돌린다 — 다음에 열 때는 카드');
  });
}

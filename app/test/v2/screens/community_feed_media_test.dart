// 카드와 상세가 글에 붙은 사진·영상을 그린다 (#429 · #465).
//
// `community_feed_test.dart` 와 같은 방식 — 진짜 `CommunityRepository` 에 `MockClient`.
// 그림 자체는 테스트에서 안 내려온다(네트워크 없음) — 자리·개수·"1/N"·전체 보기를 본다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';
import 'package:heat_trip_flutter/v2/domain/date_label.dart';
import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/aurora.dart';
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

Map<String, Object?> _post({
  int id = 12,
  List<Map<String, Object?>> media = const [],
  String title = '서울숲 아침 산책 코스 추천',
  String body = '이른 아침엔 사람이 적어서 대형견도 편해요.',
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'loc': '서울숲',
      'contentId': '126508',
      'title': title,
      'body': body,
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

/// 폰 폭에 긴 표면 — 사진이 카드 폭만큼 높아서 기본 표면(800×600)에서는 카드 하나가
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

  testWidgets('여러 장이면 캐러셀 — "1/6" 과 점이 뜨고, 그림은 보이는 한 장만 받는다 (#465)', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [for (var i = 1; i <= 6; i++) _media(i)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-carousel')), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget, reason: '사진이 여럿이라는 것을 첫눈에 — Instagram 의 숫자');
    expect(find.text('+2'), findsNothing, reason: '2×2 격자와 +N 은 없다 — 사진이 카드 폭의 절반이라 안 보였다');
    expect(find.descendant(of: _strip, matching: find.byType(Image)), findsOneWidget,
        reason: '목록 한 장에 URL 여섯이 와도 그림은 보이는 한 장만 내려받는다');
    expect(tester.takeException(), isNull);
  });

  testWidgets('캐러셀은 첫 장의 비율을 전부가 따르고, 저절로 넘어가지 않는다', (tester) async {
    _phone(tester);
    final repo = _repo([
      _post(media: [_media(1, width: 1600, height: 1200), _media(2, width: 720, height: 1280)])
    ]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    final aspect = tester.widget<AspectRatio>(find.descendant(of: _strip, matching: find.byType(AspectRatio)));
    expect(aspect.aspectRatio, closeTo(4 / 3, 1e-9), reason: '둘째 장이 세로여도 자리는 첫 장 기준이다');
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('1/2'), findsOneWidget, reason: 'Material 캐러셀 — 자동 넘김 없음');
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

  testWidgets('넷째 장까지 넘겨서 누르면 전체 보기가 그 자리에서 열린다 — 카드가 아니라 사진이 먼저 받는다', (tester) async {
    _phone(tester);
    final repo = _repo([_post(media: [for (var i = 1; i <= 6; i++) _media(i)])]);
    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    final carousel = find.byKey(const Key('post-media-carousel'));
    for (var i = 0; i < 3; i++) {
      await tester.drag(carousel, const Offset(-400, 0));
      await tester.pumpAndSettle();
    }
    expect(find.text('4/6'), findsOneWidget, reason: '세 번 넘겼으니 넷째');

    await tester.tap(carousel);
    // 카드의 사진에는 두 번 탭(귀여워요, #451 4번)이 있어 한 번 탭은 판정 시간(300ms) 뒤에 온다.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-viewer')), findsOneWidget);
    expect(find.text('4 / 6'), findsOneWidget, reason: '넷째 장을 눌렀으니 넷째부터');
    expect(find.byType(PostDetailScreen), findsNothing, reason: '카드의 상세 열기가 가로채지 않는다');

    await tester.tap(find.byKey(const Key('post-media-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-media-viewer')), findsNothing);
  });

  testWidgets('상세에도 같은 캐러셀이 뜨고, 세로 사진은 4:5 그대로다 — 자르는 것은 목록뿐', (tester) async {
    _phone(tester);
    final json = _post(media: [_media(1, width: 1080, height: 1350), _media(2)]);
    final repo = _repo([json], detail: json);
    await tester.pumpWidget(_host(PostDetailScreen(post: CommunityPost.tryParse(json)!, repository: repo)));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    final aspect = tester.widget<AspectRatio>(find.descendant(of: _strip, matching: find.byType(AspectRatio)));
    expect(aspect.aspectRatio, closeTo(4 / 5, 1e-9), reason: '상세는 글 하나가 주인공 — 4:5 까지(#440)');
  });

  testWidgets('좁은 화면·큰 글씨에서도 캐러셀이 넘치지 않는다 — 한 장·둘·여섯', (tester) async {
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
        // 카드와 같은 좌우 여백 — 사진 자리가 받는 폭이 같다.
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
  // ── 카드 밀도 (#465) — "한 화면에 글 하나만 꽉 차는 게 말이 안 돼"
  group('카드 밀도', () {
    const portrait = (width: 1080, height: 1350); // 4:5 — 인스타그램 세로 사진

    /// 실제 폰 한 화면(390×844) — 카드가 몇 장 들어오는지 잰다.
    void screen(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder cardOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(GlassCard)).first;

    testWidgets('카드에서는 세로 사진이 1:1 까지만 — 4:5 였던 자리다. 사진 벽은 4:5 그대로', (tester) async {
      _phone(tester);
      final repo = _repo([_post(id: 12, media: [_media(1, width: portrait.width, height: portrait.height)])]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();

      final aspect = tester.widget<AspectRatio>(find.descendant(of: _strip, matching: find.byType(AspectRatio)));
      expect(aspect.aspectRatio, closeTo(1, 1e-9),
          reason: 'Reddit 의 카드 — 세로 사진은 정사각 근처로 자르고 원본은 전체 보기에서');

      await tester.tap(find.byKey(const Key('feed-view-grid')));
      await tester.pumpAndSettle();
      final tile = tester.widget<AspectRatio>(find.descendant(
        of: find.byKey(const Key('photo-tile-12')),
        matching: find.byType(AspectRatio),
      ));
      expect(tile.aspectRatio, closeTo(4 / 5, 1e-9), reason: '벽은 사진이 주인공 — 4:5 까지 그대로');
    });

    testWidgets('한 화면에 사진 글이 한 장을 넘는다 — 둘째 카드의 사진이 보인다', (tester) async {
      screen(tester);
      final repo = _repo([
        _post(id: 12, title: '첫 글', media: [_media(1, width: portrait.width, height: portrait.height)]),
        _post(id: 13, title: '둘째 글', media: [_media(2, width: portrait.width, height: portrait.height)]),
      ]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();

      final first = tester.getRect(cardOf('첫 글'));
      expect(first.height, lessThan(560),
          reason: '이슈 실측 — 예전 카드는 ≈750 이라 화면(844)에서 머리말을 빼면 한 장도 다 안 들어왔다');
      final secondStrip = tester.getRect(find.byKey(const Key('post-media-strip')).at(1));
      expect(secondStrip.top, lessThan(844 - 100),
          reason: '둘째 글의 사진 윗부분이 알약 위로 보인다 — "한 화면에 글 하나" 가 아니다');
    });

    testWidgets('작성자 줄은 아바타 28 — 닉네임과 날짜가 같은 높이, 게시판 칩은 그 아래 장소와 한 줄', (tester) async {
      _phone(tester);
      final repo = _repo([_post(media: [_media(1)])]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();

      final avatar = find.ancestor(of: find.text('보'), matching: find.byType(Container)).first;
      expect(tester.getSize(avatar), const Size(28, 28), reason: '예전 40 — 작성자 줄이 62 에서 28 로');
      final nick = tester.getCenter(find.text('보리아빠'));
      final date = tester.getCenter(find.text(dateLabel(DateTime.parse('2026-09-01T07:30:00Z'))));
      final chip = tester.getCenter(find.text(CommunityBoard.walkReview.label));
      final loc = tester.getCenter(find.text('서울숲'));
      expect(date.dy, moreOrLessEquals(nick.dy, epsilon: 2));
      expect(chip.dy, greaterThan(nick.dy + 14), reason: '칩은 둘째 줄 — 2.0배·320dp 에서 날짜와 한 줄에 못 들어간다');
      expect(loc.dy, moreOrLessEquals(chip.dy, epsilon: 4), reason: '장소는 칩과 같은 줄');
      final title = tester.getTopLeft(find.text('서울숲 아침 산책 코스 추천'));
      expect(title.dy - tester.getTopLeft(avatar).dy, lessThan(70),
          reason: '아바타 위에서 제목까지 — 예전(아바타 40 + 두 줄 + 여백 12)은 74 를 넘었다');
    });

    testWidgets('본문은 두 줄까지 — 나머지는 상세에서', (tester) async {
      _phone(tester);
      final body = List.filled(30, '이른 아침엔 사람이 적어서 대형견도 편해요.').join(' ');
      final repo = _repo([_post(body: body)]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(find.text(body));
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.getSize(find.text(body)).height, lessThan(13.5 * 1.45 * 3),
          reason: '세 줄이면 한 화면에 글이 하나 덜 들어온다');
    });

    testWidgets('액션 한 줄 — 반응 셋이 같은 높이에 수와 함께, 댓글 수는 그 줄 오른쪽 끝', (tester) async {
      _phone(tester);
      final repo = _repo([_post()]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();

      final help = tester.getCenter(find.text('도움돼요'));
      final cute = tester.getCenter(find.text('귀여워요'));
      final empathy = tester.getCenter(find.text('공감'));
      expect(cute.dy, moreOrLessEquals(help.dy, epsilon: 1));
      expect(empathy.dy, moreOrLessEquals(help.dy, epsilon: 1));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      final count = tester.getCenter(find.byKey(const Key('post-comment-count-12')));
      expect(count.dy, moreOrLessEquals(help.dy, epsilon: 1), reason: '댓글 수도 같은 줄 — 액션 한 줄');
      expect(count.dx, greaterThan(empathy.dx), reason: '댓글 수는 오른쪽 끝');
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget, reason: '귀여워요는 하트 — 좋아요 자리');
    });

    testWidgets('목록(간단히) 보기에는 오른쪽 섬네일 — 사진 없는 글에는 없고, 영상은 재생 표시 (Reddit compact)',
        (tester) async {
      _phone(tester);
      final repo = _repo([
        _post(id: 12, media: [_media(1, kind: 'video', width: 1280, height: 720), _media(2)]),
        _post(id: 13),
      ]);
      await tester.pumpWidget(_host(FeedScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('feed-view-list')));
      await tester.pumpAndSettle();

      final thumb = find.byKey(const Key('post-thumb-12'));
      expect(thumb, findsOneWidget);
      expect(find.byKey(const Key('post-thumb-13')), findsNothing, reason: '사진 없는 글은 섬네일 자리도 없다');
      expect(tester.getSize(thumb), const Size(56, 56));
      expect(find.descendant(of: thumb, matching: find.byIcon(Icons.play_circle_fill_rounded)), findsOneWidget);
      final image = tester.widget<Image>(find.descendant(of: thumb, matching: find.byType(Image)));
      expect((image.image as NetworkImage).url, endsWith('/1.jpg'), reason: '첫 장의 썸네일');
      expect(tester.takeException(), isNull);
    });
  });
}

// 커뮤니티 화면 둘이 **서버에서 온 것을 그리는가** (이슈 #171).
//
// `family_screen_test.dart` 와 같은 방식이다 — 리포지토리를 목으로 갈아끼우지 않고
// **진짜 CommunityRepository 에 MockClient 를 꽂는다.** 그래야 JSON 파싱·경로·실패
// 분류까지 한 번에 지난다.
//
// 이 파일이 생기기 전, 이 두 화면은 어느 앱 테스트에도 안 잡혔다. 목록은 상수 4건이었고
// 반응은 화면 로컬 토글이었으니 잡을 것도 없었다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  final String? access;

  const _FakeTokenStore(this.access);

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => access == null ? null : 'RT-1';

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

Map<String, Object?> _post({
  int id = 12,
  String board = 'walk_review',
  Object? mine = const <String>[],
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': board,
      'loc': '서울숲',
      'contentId': '126508',
      'title': '서울숲 아침 산책 코스 추천',
      'body': '이른 아침엔 사람이 적어서 대형견도 편해요.',
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
    };

({CommunityRepository repo, List<http.BaseRequest> calls}) fixture(
  Future<http.Response> Function(http.Request request) handler, {
  String? token = 'AT-1',
  Map<String, Object?>? detail,
}) {
  final calls = <http.BaseRequest>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      calls.add(request);
      // 상세 화면은 진입할 때 글을 **다시 읽는다** — 목록이 넘긴 것은 그때의 세션으로
      // 읽은 값이라, 게스트로 훑다가 로그인한 사람에게는 낡았다.
      if (request.method == 'GET' &&
          RegExp(r'^/api/community/posts/\d+$').hasMatch(request.url.path)) {
        return _json(detail ?? _post());
      }
      return handler(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(token),
  );
  return (
    repo: CommunityRepository(baseUrl: _base, client: client),
    calls: calls,
  );
}

Widget _host(Widget child) => MaterialApp(home: child);

/// 논리 폭 [widthDp] 의 화면으로 바꾼다 — 물리 픽셀이 아니라 **dp** 로 적는다.
///
/// 이걸 안 걸면 창이 **800x600** 이다. 어떤 폰보다 넓어서, 폭 때문에 나는 넘침은
/// 여기 있는 어떤 테스트에도 안 걸린다(#386 에서 배운 것이다).
void useWidth(WidgetTester tester, double widthDp, {double heightDp = 780}) {
  const ratio = 3.0;
  tester.view.physicalSize = Size(widthDp * ratio, heightDp * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
}

/// 글자 배율만 바꾼 호스트. 화면 크기는 view 에서 온 것을 그대로 둔다 — MediaQueryData 를
/// 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
Widget _scaled(Widget child, double textScale) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('목록이 서버에서 온다 — 제목과 게시판 라벨을 그린다', (tester) async {
    final f = fixture((_) async => _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        }));

    await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.text('서울숲 아침 산책 코스 추천'), findsOneWidget);
    expect(find.text('산책로 후기'), findsOneWidget,
        reason: 'board 값은 walk_review 이고 화면 문구는 한글이다');
    expect(find.text('1개의 글'), findsOneWidget);
  });

  testWidgets('백엔드를 못 부르면 빈 목록이 아니라 이유와 다시 시도가 뜬다', (tester) async {
    var attempts = 0;
    final f = fixture((_) async {
      attempts++;
      throw http.ClientException('연결 실패');
    });

    await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.textContaining('불러오지 못했어요'), findsOneWidget,
        reason: '빈 목록은 "아직 글이 없다" 로 읽힌다 — 서버가 죽은 것을 아무도 모른다');
    expect(find.text('아직 글이 없어요 · 첫 이야기를 남겨보세요'), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(attempts, 2, reason: '다시 시도가 실제로 다시 부른다');
  });

  testWidgets('게시판을 고르면 그 board 로 다시 부른다', (tester) async {
    final f = fixture((_) async => _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        }));

    await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('건강·병원').last);
    await tester.pumpAndSettle();

    expect(f.calls.last.url.queryParameters['board'], 'health');
  });

  testWidgets('로그아웃 상태에서 상세가 보이고 반응은 꺼진 채, 입력칸 대신 안내가 뜬다',
      (tester) async {
    final f = fixture(
      (_) async => _json({
        'items': const [],
        'nextCursor': null,
        'hasMore': false,
      }),
      token: null,
      // 상세가 다시 읽을 때도 게스트 응답이어야 한다 — mine 이 null 인 것이 신호다.
      detail: _post(mine: null),
    );
    final post = CommunityPost.tryParse(_post(mine: null))!;

    await tester.pumpWidget(
      _host(PostDetailScreen(post: post, repository: f.repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('서울숲 아침 산책 코스 추천'), findsOneWidget);
    expect(find.text('로그인하면 댓글과 반응을 남길 수 있어요'), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: '쓰고 나서 401 을 내면 쓴 글자를 잃고 나서야 로그인이 필요한 것을 안다');

    // 반응은 집계만 보이고 하이라이트는 전부 꺼져 있다.
    expect(find.text('도움돼요'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('반응을 누르면 서버 응답의 집계를 그린다 — 로컬에서 세지 않는다',
      (tester) async {
    final f = fixture((request) async {
      if (request.method == 'POST') {
        // 서버가 준 값은 8 이 아니라 **9** 다. 로컬에서 +1 했다면 8 이 그려진다.
        return _json({
          'help': 9,
          'cute': 3,
          'empathy': 2,
          'mine': const ['help'],
        });
      }
      return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
    });
    final post = CommunityPost.tryParse(_post())!;

    await tester.pumpWidget(
      _host(PostDetailScreen(post: post, repository: f.repo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('도움돼요'));
    await tester.pumpAndSettle();

    expect(find.text('9'), findsOneWidget);
    expect(find.text('8'), findsNothing,
        reason: '로컬에서 세면 남이 같은 시간에 누른 것이 안 보인다');
    expect(
      f.calls.last.url.path,
      '/api/community/posts/12/reactions/help',
    );
  });

  testWidgets('댓글을 보내면 서버가 준 것이 스레드에 붙는다', (tester) async {
    final f = fixture((request) async {
      if (request.method == 'POST') {
        return _json({
          'id': 5,
          'author': {'userId': 7, 'nickname': '보리아빠'},
          'body': '저도 가봐야겠어요',
          'createdAt': '2026-09-01T09:00:00Z',
        }, status: 201);
      }
      return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
    });
    final post = CommunityPost.tryParse(_post())!;

    await tester.pumpWidget(
      _host(PostDetailScreen(post: post, repository: f.repo)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '저도 가봐야겠어요');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('저도 가봐야겠어요'), findsOneWidget);
    // 화면이 세는 것이 아니라 **서버가 센 값**이다. 픽스처의 글은 commentCount 가 1 이고
    // 방금 하나를 달았으니 2 다 — 목록 카드의 숫자와 같은 값이어야 한다.
    expect(find.text('댓글 2'), findsOneWidget);
  });

  testWidgets('댓글을 못 불러오면 빈 스레드가 아니라 이유가 뜬다', (tester) async {
    final f = fixture((_) async => throw http.ClientException('연결 실패'));
    final post = CommunityPost.tryParse(_post())!;

    await tester.pumpWidget(
      _host(PostDetailScreen(post: post, repository: f.repo)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.text('첫 댓글을 남겨보세요.'), findsNothing,
        reason: '빈 스레드는 "아직 댓글이 없다" 로 읽힌다');
  });

  // ── 카드 발치의 댓글 줄이 큰 글자에서 안 넘친다 (#432) ──────────────────
  //
  // `💬 댓글 N개 · 자세히 보기 …… >` 줄이다. `Text` 가 flex 가 아니라 Row 가 폭을 무한대로
  // 주고, `Spacer` 는 남은 공간이 음수여도 0 까지만 줄어든다 — #402 와 같은 모양이다.
  // 360dp·1.5배에서 **4px** 넘쳤다(2026-09-13 실측). 사진·동영상(#429)과 무관하다 —
  // 이 줄은 아이콘·글자·화살표뿐이라 첨부가 있든 없든 같은 값으로 넘친다.
  //
  // 2.0배는 여기서 안 본다. 같은 화면의 다른 세 줄(머리말·필터 줄·카드 머리말)이 2.0배에서
  // 먼저 터져서, 화면 전체로 예외를 보는 이 방식으로는 이 줄을 판정할 수 없다. 셋은 #433
  // 에서 고치고, 그때 2.0배 케이스를 여기에 더한다.

  group('카드 발치의 댓글 줄', () {
    Future<void> pumpFeed(
      WidgetTester tester, {
      required double width,
      required double scale,
      Map<String, Object?>? post,
    }) async {
      final f = fixture((_) async => _json({
            'items': [post ?? _post()],
            'nextCursor': null,
            'hasMore': false,
          }));
      useWidth(tester, width);
      await tester.pumpWidget(_scaled(FeedScreen(repository: f.repo), scale));
      await tester.pumpAndSettle();
    }

    Rect footerRowRect(WidgetTester tester) => tester.getRect(find
        .ancestor(
            of: find.byIcon(Icons.chevron_right), matching: find.byType(Row))
        .first);

    testWidgets('360dp · 글자 1.5배에서 안 넘친다 — 4px 넘치던 자리다', (tester) async {
      await pumpFeed(tester, width: 360, scale: 1.5);

      expect(tester.takeException(), isNull,
          reason: '넘치면 프레임워크가 예외를 남긴다 — 노란 줄무늬는 그 예외의 그림이다');
    });

    testWidgets('댓글이 세 자리여도, 글쓴이 동네가 붙어도 360dp · 1.5배에서 안 넘친다',
        (tester) async {
      // 세 자리면 360dp 에서 1.3배부터 넘치던 값이다(이슈 실측 1.5배 42px).
      await pumpFeed(tester, width: 360, scale: 1.5, post: {
        ..._post(),
        'commentCount': 999,
        'authorDistrict': '성동구',
      });

      expect(tester.takeException(), isNull);
      expect(find.textContaining('댓글 999개'), findsOneWidget,
          reason: '줄이더라도 개수는 남는다 — 줄어드는 것은 뒤쪽 안내("자세히 보기")다');
      final label = tester.getSize(find.textContaining('댓글 999개'));
      expect(label.height, lessThan(12.5 * 1.5 * 2),
          reason: '두 줄로 접지 않는다 — 한글은 음절 사이에서 줄이 바뀌어 "보/기" 로 갈라진다');
    });

    testWidgets('좁아도 화살표는 오른쪽 끝에 그대로 보인다', (tester) async {
      await pumpFeed(tester, width: 360, scale: 1.5, post: {
        ..._post(),
        'commentCount': 999,
      });

      final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
      expect(chevron.right, moreOrLessEquals(footerRowRect(tester).right),
          reason: '글자가 화살표를 밀어내면 "더 볼 수 있다" 는 신호가 화면 밖으로 나간다');
    });

    testWidgets('보통 배율에서는 지금 모양 그대로다 — 글자는 왼쪽, 화살표는 오른쪽 끝',
        (tester) async {
      await pumpFeed(tester, width: 360, scale: 1.0);

      expect(tester.takeException(), isNull);
      final row = footerRowRect(tester);
      final label = find.text('댓글 1개 · 자세히 보기');
      final labelBox = tester.getRect(label);
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
      expect(labelBox.left, lessThan(row.left + 40),
          reason: '아이콘(16) 과 간격(6) 바로 뒤에 글자가 온다');
      expect(chevron.right, moreOrLessEquals(row.right));

      // 글자 **상자**가 아니라 **그려진 글자**로 잰다 — Expanded 라 상자는 화살표까지 닿고,
      // 꽉 찬 제약에서는 textSize 도 상자 폭을 돌려준다. 글자 폭은 intrinsic 으로 잰다.
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse,
          reason: '보통 배율에서는 안내가 통째로 보인다 — 말줄임은 좁을 때만');
      final ink = paragraph.getMaxIntrinsicWidth(double.infinity);
      expect(labelBox.left + ink, lessThan(chevron.left),
          reason: '글자와 화살표 사이가 비어 있다 — 글자가 화살표까지 자라면 안 된다');
    });
  });
}

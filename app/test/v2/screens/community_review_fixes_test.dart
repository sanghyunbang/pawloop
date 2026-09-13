// 적대적 리뷰가 찾은 앱 쪽 결함들을 잠근다 — #170~#172 의 회귀.
//
// 리뷰는 오늘 올린 커뮤니티 코드를 일곱 축으로 훑고, 나온 것마다 서로 다른 렌즈의
// 반박자 셋을 붙였다. 여기 있는 것들은 2/3 반박을 견딘 뒤 내가 코드에서 다시 확인한
// 것들이다. 각 테스트의 이름이 <b>고치기 전에 사용자가 겪던 일</b>이다.
//
// `community_feed_test.dart` 와 같은 방식이다 — 진짜 리포지토리에 `MockClient` 를 꽂는다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

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

Map<String, Object?> _post({
  int id = 12,
  String board = 'walk_review',
  String title = '서울숲 아침 산책 코스 추천',
  String? loc = '서울숲',
  int commentCount = 1,
  Object? mine = const <String>[],
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': board,
      'loc': loc,
      'contentId': '126508',
      'title': title,
      'body': '이른 아침엔 사람이 적어서 대형견도 편해요.',
      'commentCount': commentCount,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
    };

Map<String, Object?> _comment(int id) => {
      'id': id,
      'author': {'userId': 9, 'nickname': '초코맘'},
      'body': '스레드 본문 $id',
      'createdAt': '2026-09-01T08:00:00Z',
    };

CommunityRepository _repo(MockClient inner) => CommunityRepository(
      baseUrl: _base,
      client: AuthedClient(inner: inner, baseUrl: _base, store: _FakeTokenStore()),
    );

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('댓글 21번째부터도 볼 수 있다 — 첫 장만 읽고 커서를 버리면 영영 못 본다',
      (tester) async {
    var page = 0;
    final repo = _repo(MockClient((request) async {
      if (request.url.path.endsWith('/comments')) {
        final first = request.url.queryParameters['cursor'] == null;
        page++;
        return _json({
          'items': first
              ? [for (var i = 1; i <= 20; i++) _comment(i)]
              : [_comment(21)],
          'nextCursor': first ? 'CURSOR-2' : null,
          'hasMore': first,
        });
      }
      return _json(_post(commentCount: 21));
    }));

    await tester.pumpWidget(_host(
      PostDetailScreen(
          post: CommunityPost.tryParse(_post(commentCount: 21))!,
          repository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('스레드 본문 21'), findsNothing, reason: '아직 첫 장만 왔다');

    // ListView 는 화면 밖 자식을 안 만든다. 버튼은 스무 개 아래에 있다.
    await tester.scrollUntilVisible(find.text('댓글 더 보기'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('댓글 더 보기'));
    await tester.pumpAndSettle();

    expect(page, 2);
    await tester.scrollUntilVisible(find.text('스레드 본문 21'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('스레드 본문 21'), findsOneWidget);
    expect(find.text('댓글 더 보기'), findsNothing, reason: '마지막 장이면 버튼이 없다');
  });

  testWidgets('스레드 머리의 숫자는 서버가 센 값이다 — 불러온 장 수가 아니다',
      (tester) async {
    final repo = _repo(MockClient((request) async {
      if (request.url.path.endsWith('/comments')) {
        return _json({
          'items': [for (var i = 1; i <= 20; i++) _comment(i)],
          'nextCursor': 'CURSOR-2',
          'hasMore': true,
        });
      }
      return _json(_post(commentCount: 34));
    }));

    await tester.pumpWidget(_host(
      PostDetailScreen(
          post: CommunityPost.tryParse(_post(commentCount: 34))!,
          repository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('댓글 34'), findsOneWidget,
        reason: '"댓글 34개" 를 보고 들어와 20 이라고 적힌 화면을 만나면 지워졌다고 읽는다');
  });

  testWidgets('상세는 글을 다시 읽는다 — 목록이 넘긴 것은 그때의 세션으로 읽은 값이다',
      (tester) async {
    // 게스트로 목록을 훑다가 로그인하고 돌아온 상황. 목록의 글은 아직 mine == null 이다.
    final stale = CommunityPost.tryParse(_post(mine: null))!;

    final repo = _repo(MockClient((request) async {
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      // 서버는 이제 로그인한 사람으로 본다.
      return _json(_post(mine: const <String>[]));
    }));

    await tester.pumpWidget(_host(
      PostDetailScreen(post: stale, repository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('로그인하면 댓글과 반응을 남길 수 있어요'), findsNothing,
        reason: '로그인했는데 낡은 스냅샷 때문에 댓글도 반응도 막히면 안 된다');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('게시판을 빠르게 바꾸면 늦게 온 응답이 화면을 되돌리지 않는다',
      (tester) async {
    // 첫 요청(전체)을 늦게 돌려주고 두 번째(건강·병원)를 먼저 돌려준다.
    //
    // Completer 로는 안 된다 — 위젯 테스트의 **가짜 시간**에서는 바깥에서 complete 해도
    // 그 이어짐이 안 깨어난다. 실제로 그렇게 썼다가 가드를 빼도 초록불이 나는,
    // 아무것도 안 지키는 테스트가 됐다. Future.delayed 는 가짜 시간이 밀어 준다.
    final repo = _repo(MockClient((request) async {
      final board = request.url.queryParameters['board'];
      if (board == null) {
        await Future<void>.delayed(const Duration(seconds: 5));
        return _json({
          'items': [_post(id: 1, title: '전체에서 온 글')],
          'nextCursor': null,
          'hasMore': false,
        });
      }
      return _json({
        'items': [_post(id: 2, board: 'health', title: '건강 게시판 글')],
        'nextCursor': null,
        'hasMore': false,
      });
    }));

    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pump();

    // **pumpAndSettle 을 쓰면 안 된다.** 그것은 가짜 시간을 몇 초씩 밀어서, 시트를 여는
    // 사이에 느린 첫 응답이 이미 도착해 버린다 — 그러면 경합 자체가 안 일어나고
    // 테스트는 가드를 빼도 초록불이다(실제로 그랬다). 시트 애니메이션만큼만 민다.
    await tester.tap(find.text('전체'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('건강·병원').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('건강 게시판 글'), findsOneWidget);

    // 이제 첫 요청이 도착한다. 세대 검사가 없으면 이게 화면을 덮는다.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(find.text('건강 게시판 글'), findsOneWidget,
        reason: '늦게 온 전체 응답이 지금 고른 게시판을 덮으면 필터가 안 먹는 것으로 보인다');
    expect(find.text('전체에서 온 글'), findsNothing);
  });

  testWidgets('글을 열어 보기만 하고 나오면 목록을 다시 부르지 않는다', (tester) async {
    var feedCalls = 0;
    final repo = _repo(MockClient((request) async {
      if (request.url.path == '/api/community/posts') {
        feedCalls++;
        return _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        });
      }
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      return _json(_post());
    }));

    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(feedCalls, 1);

    await tester.tap(find.text('서울숲 아침 산책 코스 추천'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(feedCalls, 1,
        reason: '무조건 다시 부르면 더 보기로 쌓아 둔 장이 전부 사라지고 스크롤이 맨 위로 간다');
  });

  testWidgets('상세에서 반응을 누르고 나오면 목록을 다시 부른다', (tester) async {
    var feedCalls = 0;
    final repo = _repo(MockClient((request) async {
      if (request.url.path == '/api/community/posts') {
        feedCalls++;
        return _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        });
      }
      if (request.method == 'POST' && request.url.path.contains('/reactions/')) {
        return _json({
          'help': 8,
          'cute': 3,
          'empathy': 2,
          'mine': const ['help'],
        });
      }
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      return _json(_post());
    }));

    await tester.pumpWidget(_host(FeedScreen(repository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('서울숲 아침 산책 코스 추천'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('도움돼요'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(feedCalls, 2, reason: '집계가 바뀌었으니 목록의 숫자도 따라가야 한다');
  });

  testWidgets('이모지가 섞여 상한을 넘으면 보내기 전에 막는다 — 세는 단위가 다르다',
      (tester) async {
    // Flutter 의 maxLength 는 **글자(grapheme)** 로 세고 서버의 @Size 는 자바
    // String.length() — **UTF-16 코드 단위**로 센다. 이모지 하나가 2 다.
    var sent = 0;
    final repo = _repo(MockClient((_) async {
      sent++;
      return _json(_post(), status: 201);
    }));

    await tester.pumpWidget(_host(PostWriteScreen(repository: repo)));
    await tester.pumpAndSettle();

    // 화면에서는 200자 이하로 보이지만 UTF-16 으로는 200 을 넘는다.
    final emojiTitle = '🐾' * 120;
    expect(emojiTitle.characters.length, lessThan(CommunityRepository.maxTitleLength));
    expect(emojiTitle.length, greaterThan(CommunityRepository.maxTitleLength));

    await tester.enterText(find.byType(TextField).first, emojiTitle);
    await tester.enterText(find.byType(TextField).last, '본문');
    // 사진 칸이 맨 위로 오면서(#451) 기본 표면(800×600)에서는 올리기 버튼이 화면 밖이다 —
    // 목록이 안 만든 위젯은 찾을 수 없으니 먼저 끌어 올린다.
    await tester.dragUntilVisible(find.text('올리기'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('제목이 너무 길어요'), findsOneWidget);
    expect(sent, 0, reason: '보내면 400 을 받고, 사용자는 무엇을 지워야 하는지 모른다');
  });
}

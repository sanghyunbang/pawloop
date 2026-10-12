// 따로 보이는 "차단" 과, 차단한 순간 사라지는 글·댓글 — 애플 App Review Guideline 1.2.
//
// 1.2 는 차단에 세 가지를 요구한다: 악성 이용자를 **차단하는 수단**이 있을 것 · 차단하면 **개발자에게
// 알릴 것** · 차단한 사람의 콘텐츠가 **피드에서 즉시 사라질 것**. 여기서 재는 것은 앱의 몫이다.
//
//  1. 남의 글·댓글에 **신고와 따로** "차단" 이 보인다. 지금까지는 신고 시트 안의 체크칸뿐이라, 신고할
//     생각이 없는 사람은 차단이 있는 줄도 몰랐다.
//  2. 확인 창이 무엇이 일어나는지 셋을 말한다 — 사라짐 · 운영자 알림 · 상대 비고지.
//  3. 확인하면 계약의 키(`userId`)로 `POST /api/blocks` 가 가고, **다시 부르지 않고** 목록에서 빠진다.
//  4. 차단한 사람의 글을 직접 열면 "차단한 사용자의 글이에요" 만 남고 펼 수 없다.
//
// 가짜 서버는 **계약대로** 응답한다 — `openapi.yaml` 의 `Post` · `Comment` · `PostPage`(키 `items`)이고,
// 차단 뒤에는 지금 서버처럼 그 사람의 글을 목록에서 빼고 상세에는 `hiddenByBlock: true` 를 붙인다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/blocked_authors.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/session_traces.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/place_posts_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';

const _base = 'https://api.example.test';
const _me = 7;

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

/// 계약의 `Post`. 제목·본문에 글 번호를 넣어 어느 글이 남았는지 글자로 가른다.
Map<String, Object?> _post(int id, {required int author, bool hidden = false, String? contentId}) => {
      'id': id,
      'author': {'userId': author, 'nickname': author == _me ? '나' : '이웃$author'},
      'board': 'free',
      'loc': contentId == null ? null : '서울숲',
      'contentId': contentId,
      'title': '글 $id 제목',
      'body': '글 $id 본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': const <Object?>[],
      'bookmarked': false,
      'hiddenByBlock': hidden,
    };

/// 계약의 `Comment`.
Map<String, Object?> _comment(int id, {required int author}) => {
      'id': id,
      'author': {'userId': author, 'nickname': author == _me ? '나' : '이웃$author'},
      'body': '댓글 $id 내용',
      'createdAt': '2026-09-01T08:00:00Z',
      'hiddenByBlock': false,
    };

/// 지금 서버처럼 구는 가짜 — 차단하면 그 사람의 글·댓글을 목록에서 빼고, 상세에는 표시를 붙인다.
class _Server {
  _Server({required this.posts, this.comments = const [], this.blockStatus = 201});

  final List<Map<String, Object?>> posts;
  final List<Map<String, Object?>> comments;
  final int blockStatus;

  final Set<int> blocked = <int>{};
  final List<Map<String, Object?>> blockBodies = [];
  int listCalls = 0;
  int commentCalls = 0;

  int _authorOf(Map<String, Object?> json) => ((json['author'] as Map)['userId'] as num).toInt();

  late final CommunityRepository repo = CommunityRepository(
    baseUrl: _base,
    client: AuthedClient(
      inner: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' && path == '/api/blocks') {
          blockBodies.add((jsonDecode(request.body) as Map).cast<String, Object?>());
          if (blockStatus != 201) return _json({'error': {}}, status: blockStatus);
          blocked.add((blockBodies.last['userId'] as num).toInt());
          return http.Response('', 201);
        }
        if (request.method == 'POST' && path.endsWith('/reports')) {
          // 계약의 `ReportReceipt` — 접수증이 응답의 전부다.
          return _json({'reportId': 5, 'createdAt': '2026-09-03T01:00:00Z'}, status: 201);
        }
        if (path.endsWith('/comments')) {
          commentCalls++;
          return _json({
            'items': [for (final c in comments) if (!blocked.contains(_authorOf(c))) c],
            'nextCursor': null,
            'hasMore': false,
          });
        }
        if (path == '/api/community/posts') {
          listCalls++;
          return _json({
            'items': [for (final p in posts) if (!blocked.contains(_authorOf(p))) p],
            'nextCursor': null,
            'hasMore': false,
          });
        }
        final one = RegExp(r'^/api/community/posts/(\d+)$').firstMatch(path);
        if (one != null) {
          final post = posts.firstWhere((p) => p['id'] == int.parse(one.group(1)!));
          return _json({...post, 'hiddenByBlock': blocked.contains(_authorOf(post)) || post['hiddenByBlock'] == true});
        }
        if (path.endsWith('/summary')) {
          return _json({'posts': posts.length, 'photos': 0, 'walks': 0});
        }
        return _json({'error': {}}, status: 404);
      }),
      baseUrl: _base,
      store: _FakeTokenStore(),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openDetail(WidgetTester tester, _Server server, Map<String, Object?> post) async {
  await tester.pumpWidget(MaterialApp(
    home: PostDetailScreen(post: CommunityPost.tryParse(post)!, repository: server.repo),
  ));
  await tester.pumpAndSettle();
}

Future<void> _confirmBlock(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('block-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BlockedAuthors.clear();
    AuthState.signInForTest(const AuthUser(id: _me, nickname: '나'));
  });

  tearDown(() {
    BlockedAuthors.clear();
    AuthState.resetForTest();
  });

  // ─────────────────── 1. 따로 보이는 차단 ───────────────────

  testWidgets('남의 글과 남의 댓글에 신고와 따로 "차단" 이 보인다', (tester) async {
    _phone(tester);
    final server = _Server(
      posts: [_post(12, author: 99)],
      comments: [_comment(1, author: 98), _comment(2, author: _me)],
    );
    await _openDetail(tester, server, server.posts.first);

    expect(find.byKey(const Key('block-post')), findsOneWidget,
        reason: '신고 시트 안의 체크칸만 있으면, 신고할 생각이 없는 사람은 차단이 있는 줄 모른다');
    expect(find.byKey(const Key('block-comment-1')), findsOneWidget);
    expect(find.byKey(const Key('block-comment-2')), findsNothing, reason: '내 댓글에는 차단이 없다');
    expect(find.text('신고'), findsNWidgets(2), reason: '신고는 그대로 있다 — 차단이 그 자리를 빼앗지 않는다');
  });

  testWidgets('내 글과 탈퇴한 사람의 글에는 차단이 없다', (tester) async {
    _phone(tester);
    final mine = _Server(posts: [_post(12, author: _me)]);
    await _openDetail(tester, mine, mine.posts.first);
    expect(find.byKey(const Key('block-post')), findsNothing, reason: '자기 자신은 차단할 수 없다(서버도 400)');

    final gone = _Server(posts: [_post(13, author: 0)]);
    await _openDetail(tester, gone, gone.posts.first);
    expect(find.byKey(const Key('block-post')), findsNothing,
        reason: '탈퇴한 사람은 차단할 대상이 없다 — 0 을 차단하면 탈퇴한 모든 사람의 글이 사라진다');
  });

  // ─────────────────── 2. 확인 창 ───────────────────

  testWidgets('확인 창이 사라짐 · 운영자 알림 · 상대 비고지를 말하고, 취소하면 아무것도 안 보낸다', (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 99)]);
    await _openDetail(tester, server, server.posts.first);

    await tester.tap(find.byKey(const Key('block-post')));
    await tester.pumpAndSettle();

    expect(find.text('이웃99 님을 차단할까요?'), findsOneWidget);
    expect(find.text(blockConfirmMessage), findsOneWidget);
    expect(blockConfirmMessage, allOf(contains('사라지고'), contains('운영자에게 알림'), contains('알리지 않습니다')),
        reason: '1.2 가 요구하는 둘(사라짐 · 개발자 알림)과, 차단할지 정하는 데 결정적인 하나(상대 비고지)');

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(server.blockBodies, isEmpty);
    expect(BlockedAuthors.ids.value, isEmpty);
    expect(find.text('글 12 본문'), findsOneWidget);
  });

  // ─────────────────── 3. 차단하면 곧바로 사라진다 ───────────────────

  testWidgets('확인하면 계약의 키(userId)로 POST /api/blocks 가 가고, 글은 "차단한 사용자의 글이에요" 만 남는다',
      (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 99)], comments: [_comment(1, author: 98)]);
    await _openDetail(tester, server, server.posts.first);

    await _confirmBlock(tester, find.byKey(const Key('block-post')));

    expect(server.blockBodies, [
      {'userId': 99}
    ], reason: '계약(openapi.yaml)의 POST /api/blocks 는 required: [userId] 다');
    expect(find.text(hiddenPostMessage), findsOneWidget);
    expect(find.text('글 12 제목'), findsNothing);
    expect(find.text('글 12 본문'), findsNothing);
    expect(find.text('댓글 1 내용'), findsNothing, reason: '가려진 글 아래의 댓글 스레드도 안 그린다');
    expect(find.textContaining('차단했어요'), findsOneWidget);
  });

  testWidgets('피드에서 연 글의 작성자를 차단하고 돌아오면, 그 사람의 글이 다시 부르지 않고 사라져 있다',
      (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 99), _post(13, author: 98), _post(14, author: 99)]);
    await tester.pumpWidget(MaterialApp(home: FeedScreen(repository: server.repo)));
    await tester.pumpAndSettle();
    expect(find.text('글 14 제목'), findsOneWidget);
    final listCallsBefore = server.listCalls;

    await tester.tap(find.text('글 12 제목'));
    await tester.pumpAndSettle();
    await _confirmBlock(tester, find.byKey(const Key('block-post')));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('글 12 제목'), findsNothing);
    expect(find.text('글 14 제목'), findsNothing,
        reason: '차단은 사람 단위다 — 열어 본 글 하나가 아니라 그 사람의 글이 전부 빠진다');
    expect(find.text('글 13 제목'), findsOneWidget, reason: '남의 글은 그대로다');
    expect(server.listCalls, listCallsBefore, reason: '''
1.2 의 "즉시" 를 다시 불러오기로 채우면 '더 보기' 로 쌓은 장과 스크롤이 날아간다 — 그린 것에서 뺀다.''');
  });

  testWidgets('장소의 글에서도 차단하고 돌아오면 그 사람의 글이 바로 빠진다', (tester) async {
    _phone(tester);
    final server = _Server(posts: [
      _post(21, author: 99, contentId: '126508'),
      _post(22, author: 98, contentId: '126508'),
    ]);
    await tester.pumpWidget(MaterialApp(
        home: PlacePostsScreen(contentId: '126508', title: '서울숲', repository: server.repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-posts-tab-posts')));
    await tester.pumpAndSettle();
    final listCallsBefore = server.listCalls;

    await tester.tap(find.text('글 21 제목'));
    await tester.pumpAndSettle();
    await _confirmBlock(tester, find.byKey(const Key('block-post')));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('글 21 제목'), findsNothing);
    expect(find.text('글 22 제목'), findsOneWidget);
    expect(server.listCalls, listCallsBefore);
  });

  testWidgets('댓글 쓴 사람을 차단하면 그 사람의 댓글만 이 화면에서 바로 빠진다 — 글은 그대로다', (tester) async {
    _phone(tester);
    final server = _Server(
      posts: [_post(12, author: 98)],
      comments: [_comment(1, author: 99), _comment(2, author: 97), _comment(3, author: 99)],
    );
    await _openDetail(tester, server, server.posts.first);
    expect(find.text('댓글 1 내용'), findsOneWidget);

    await _confirmBlock(tester, find.byKey(const Key('block-comment-1')));

    expect(find.text('댓글 1 내용'), findsNothing, reason: '접지 않고 뺀다 — 1.2 는 사라지기를 요구한다');
    expect(find.text('댓글 3 내용'), findsNothing, reason: '같은 사람의 다른 댓글도 빠진다');
    expect(find.text('댓글 2 내용'), findsOneWidget);
    expect(find.text('글 12 본문'), findsOneWidget, reason: '글쓴이는 차단하지 않았다');
    expect(find.textContaining('눌러서 보기'), findsNothing);
  });

  testWidgets('차단이 실패하면 아무것도 안 빠지고 실패를 말한다 — 먼저 지우면 서버는 모르는 채 사라진다', (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 99)], blockStatus: 500);
    await _openDetail(tester, server, server.posts.first);

    await _confirmBlock(tester, find.byKey(const Key('block-post')));

    expect(server.blockBodies, hasLength(1));
    expect(BlockedAuthors.ids.value, isEmpty, reason: '성공한 뒤에만 적는다');
    expect(find.text('글 12 본문'), findsOneWidget);
    expect(find.text(hiddenPostMessage), findsNothing);
  });

  testWidgets('신고 시트에서 차단을 함께 켜도 같은 순간 사라진다 — 체크칸은 그대로 있다', (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 98)], comments: [_comment(1, author: 99)]);
    await _openDetail(tester, server, server.posts.first);

    // 댓글의 신고 — 글의 신고는 첫 번째 '신고' 다.
    await tester.tap(find.text('신고').last);
    await tester.pumpAndSettle();
    expect(find.text('이 사람의 메시지를 가리기'), findsOneWidget, reason: '신고 시트 안의 체크칸은 그대로 둔다');
    await tester.tap(find.text('광고 · 도배'));
    await tester.tap(find.text('이 사람의 메시지를 가리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();

    expect(server.blockBodies, [
      {'userId': 99}
    ]);
    expect(find.text('댓글 1 내용'), findsNothing);
    expect(find.textContaining('차단했어요'), findsOneWidget);
  });

  // ─────────────────── 4. 직접 연 차단한 사람의 글 ───────────────────

  testWidgets('차단한 사람의 글을 직접 열면 "차단한 사용자의 글이에요" 만 있고, 눌러도 펴지지 않는다', (tester) async {
    _phone(tester);
    final server = _Server(posts: [_post(12, author: 99, hidden: true)], comments: [_comment(1, author: 98)]);
    await _openDetail(tester, server, server.posts.first);

    expect(find.text(hiddenPostMessage), findsOneWidget);
    expect(find.text('글 12 제목'), findsNothing, reason: '제목만 남기면 거기 욕을 적으면 그만이다');
    expect(find.text('글 12 본문'), findsNothing);
    expect(find.textContaining('눌러서 보기'), findsNothing, reason: '1.2 — 펼치는 길이 있으면 사라진 것이 아니다');
    expect(find.byType(TextField), findsNothing, reason: '가려진 글에 댓글 입력칸을 두지 않는다');

    await tester.tap(find.text(hiddenPostMessage));
    await tester.pumpAndSettle();

    expect(find.text('글 12 본문'), findsNothing);
  });

  // ─────────────────── 머리줄이 넘치지 않는다 ───────────────────
  //
  // 신고 옆에 차단이 들어오면 글 머리줄과 댓글 줄이 좁아진다. 긴 닉네임 · 긴 장소 · 가장 긴 게시판
  // 이름 · 수정됨을 다 얹고 360dp 에서 잰다. 고치기 전(main)에는 이 조건에서 1.0배부터 넘쳤다 — 칩이
  // 줄어들지 못했고, 댓글 닉네임에 말줄임이 없었다. 글꼴은 테스트 글꼴이라 실제보다 넓다(더 엄격하다).
  for (final scale in [1.0, 1.5]) {
    testWidgets('신고 · 차단이 함께 서도 360dp · 글자 $scale배에서 머리줄과 댓글 줄이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final long = {
        ..._post(12, author: 99, contentId: '126508'),
        'author': {'userId': 99, 'nickname': '아주긴닉네임을가진이웃'},
        'board': 'walk_review',
        'loc': '서울숲 가족마당 옆 산책로',
        'updatedAt': '2026-09-02T07:30:00Z',
      };
      final server = _Server(posts: [long], comments: [
        {..._comment(1, author: 98), 'author': {'userId': 98, 'nickname': '댓글다는아주긴닉네임'}},
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: PostDetailScreen(post: CommunityPost.tryParse(long)!, repository: server.repo),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '노란 줄무늬 — 차단 버튼이 머리줄을 밀어냈다');
      expect(find.byKey(const Key('block-post')), findsOneWidget);
      expect(find.byKey(const Key('block-comment-1')), findsOneWidget);
      expect(find.text('수정됨'), findsOneWidget, reason: '날짜 아래로 옮겼을 뿐 그대로 보인다');
    });
  }

  // ─────────────────── 세션 ───────────────────

  testWidgets('로그아웃 · 세션 만료에 이 세션의 차단 기억을 비운다 — 다음 사람에게 적용되면 안 된다', (tester) async {
    BlockedAuthors.add(99);
    expect(BlockedAuthors.contains(99), isTrue);

    await clearSessionTraces();

    expect(BlockedAuthors.ids.value, isEmpty);
  });

  test('탈퇴한 사람(0)은 적지 않는다 — 적으면 탈퇴한 모든 사람의 글이 한꺼번에 사라진다', () {
    BlockedAuthors.add(0);
    expect(BlockedAuthors.ids.value, isEmpty);
  });
}

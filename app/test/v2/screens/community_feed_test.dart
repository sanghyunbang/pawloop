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
}

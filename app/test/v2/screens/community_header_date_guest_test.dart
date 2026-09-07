// 커뮤니티 — 상세 제목은 게시판 이름, 날짜에 두 자리 연도가 없고, 게스트의 반응은 로그인으로 (#331).
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
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
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

/// 올해 9월 1일 07:30Z 의 글 — 기기 시간대가 어디든 날짜는 9월 1일이다.
final int _thisYear = DateTime.now().year;

Map<String, Object?> _post({
  String board = 'walk_review',
  Object? mine = const <String>[],
  String? createdAt,
}) =>
    {
      'id': 12,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': board,
      'loc': '서울숲',
      'contentId': null,
      'title': '서울숲 아침 산책 코스 추천',
      'body': '이른 아침엔 사람이 적어서 대형견도 편해요.',
      'commentCount': 0,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': createdAt ?? '$_thisYear-09-01T07:30:00Z',
    };

CommunityRepository _repo(Map<String, Object?> post) {
  final client = AuthedClient(
    inner: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && RegExp(r'^/api/community/posts/\d+$').hasMatch(path)) {
        return _json(post);
      }
      if (request.method == 'GET' && path == '/api/community/posts') {
        return _json({'items': [post], 'nextCursor': null, 'hasMore': false});
      }
      if (path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false, 'totalCount': 0});
      }
      return _json({'error': {}}, status: 404);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return CommunityRepository(baseUrl: _base, client: client);
}

Future<void> _pumpDetail(WidgetTester t, Map<String, Object?> post) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: PostDetailScreen(post: CommunityPost.tryParse(post)!, repository: _repo(post)),
  ));
  await t.pumpAndSettle();
}

/// "26.09.01" 같은 두 자리 연도 날짜.
final RegExp _twoDigitYear = RegExp(r'\b\d{2}\.\d{2}\.\d{2}\b');

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('상세 제목 표시줄은 게시판 이름이다 — "산책 이야기" 가 아니라 "산책로 후기"', (t) async {
    await _pumpDetail(t, _post(board: 'walk_review'));

    expect(find.text('산책 이야기'), findsNothing);
    expect(find.text('산책로 후기'), findsNWidgets(2), reason: '제목 표시줄 하나 + 글 카드의 게시판 칩 하나');
  });

  testWidgets('게시판이 다르면 제목도 다르다 — "건강·병원"', (t) async {
    await _pumpDetail(t, _post(board: 'health'));

    expect(find.text('건강·병원'), findsNWidgets(2));
  });

  testWidgets('상세 날짜는 "9월 1일 HH:mm" — 두 자리 연도가 없다', (t) async {
    await _pumpDetail(t, _post());

    expect(find.textContaining('9월 1일 '), findsOneWidget);
    expect(find.textContaining(_twoDigitYear), findsNothing);
  });

  testWidgets('목록 날짜는 "9월 1일" — 두 자리 연도가 없다', (t) async {
    final post = _post();
    await t.pumpWidget(MaterialApp(home: FeedScreen(repository: _repo(post))));
    await t.pumpAndSettle();

    expect(find.text('9월 1일'), findsOneWidget);
    expect(find.textContaining(_twoDigitYear), findsNothing);
  });

  testWidgets('다른 해의 글은 "2025. 9. 1" 로 — 연도를 네 자리로 말한다', (t) async {
    await _pumpDetail(t, _post(createdAt: '2025-09-01T07:30:00Z'));

    expect(find.textContaining('2025. 9. 1 '), findsOneWidget);
    expect(find.textContaining(_twoDigitYear), findsNothing);
  });

  testWidgets('게스트가 반응을 누르면 안내와 함께 로그인 화면으로 간다 — writePost() 와 같은 길', (t) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    await _pumpDetail(t, _post(mine: null));

    await t.tap(find.text('도움돼요'));
    await t.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget, reason: '토스트만 띄우면 로그인할 곳을 찾아 헤맨다');
    expect(find.text('로그인하면 반응을 남길 수 있어요'), findsOneWidget);
  });
}

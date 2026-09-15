// 상세에서 바뀐 것을 목록이 **어떻게 나왔든** 안다 — 이슈 #548.
//
// ## 무엇이 있었나
//
// 상세는 바뀜 여부를 `Navigator.pop(_changed)` 로만 알렸고 목록이 그 값을 보고 다시 읽었다.
// 그런데 **안드로이드 뒤로가기**(제스처 · 버튼)는 결과 없이 pop 한다 — 반응을 바꾸고 시스템
// 뒤로가기로 나오면 카드가 그대로였다. 화면 안 `←` 로 나올 때만 맞았다.
//
// 안드로이드에서 시스템 뒤로가기가 기본 동작이라, **틀리는 쪽이 더 흔한 길**이었다.
//
// ## 여기서 재는 것
//
// 시스템 뒤로가기는 `flutter/navigation` 의 `popRoute` 로 온다. 그것을 그대로 보낸다 —
// `tester.pageBack()` 은 화면 안 버튼을 누르는 것이라 이 버그를 못 잡는다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _post({List<String> mine = const []}) => {
      'id': 12,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'title': '서울숲 아침 산책',
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 1, 'cute': 0, 'empathy': 0, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': const [],
      'bookmarked': false,
    };

class _Fixture {
  _Fixture(this.repo, this._requests);
  final CommunityRepository repo;
  final List<http.Request> _requests;

  /// 목록을 읽은 횟수. 화면이 처음 뜰 때 한 번이고, 다시 읽으면 늘어난다.
  int get feedLoads => _requests
      .where((r) => r.method == 'GET' && r.url.path == '/api/community/posts')
      .length;
}

_Fixture _fixture() {
  final requests = <http.Request>[];
  // 반응은 서버가 집계를 돌려준다 — 화면이 그것을 그대로 그린다.
  List<String> mine = const [];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/reactions/help')) {
        mine = request.method == 'POST' ? const ['help'] : const [];
        return _json({'help': request.method == 'POST' ? 2 : 1, 'cute': 0, 'empathy': 0, 'mine': mine});
      }
      if (path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      if (RegExp(r'^/api/community/posts/\d+$').hasMatch(path)) {
        return _json(_post(mine: mine));
      }
      return _json({'items': [_post(mine: mine)], 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

/// 안드로이드 뒤로가기 — 시스템이 `flutter/navigation` 으로 보내는 그것.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 상세의 "도움돼요". 목록 카드에도 같은 아이콘이 있어 상세 안으로 좁힌다.
Finder get _detailHelp => find.descendant(
      of: find.byType(PostDetailScreen),
      matching: find.byIcon(Icons.thumb_up_alt_outlined),
    );

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('서울숲 아침 산책'));
  await tester.pumpAndSettle();
  expect(find.byType(PostDetailScreen), findsOneWidget);
}

void main() {
  testWidgets('반응을 바꾸고 안드로이드 뒤로가기로 나오면 목록이 다시 읽는다 (#548)', (tester) async {
    _phone(tester);
    final f = _fixture();
    await tester.pumpWidget(MaterialApp(home: FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    final loadsBefore = f.feedLoads;

    await _openDetail(tester);
    await tester.tap(_detailHelp);
    await tester.pumpAndSettle();

    await _systemBack(tester);

    expect(f.feedLoads, loadsBefore + 1,
        reason: '시스템 뒤로가기는 결과 없이 pop 한다 — pop 결과로만 알리면 카드가 '
            '"안 눌렀음" 인 채로 남는다');
  });

  testWidgets('화면 안 ← 로 나와도 한 번만 읽는다 — 두 길이 겹치지 않는다', (tester) async {
    _phone(tester);
    final f = _fixture();
    await tester.pumpWidget(MaterialApp(home: FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    final loadsBefore = f.feedLoads;

    await _openDetail(tester);
    await tester.tap(_detailHelp);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(PostDetailScreen), matching: find.byIcon(Icons.arrow_back)));
    await tester.pumpAndSettle();

    expect(f.feedLoads, loadsBefore + 1,
        reason: 'pop 결과와 알림을 둘 다 보면 이 길만 두 번 읽는다');
  });

  testWidgets('아무것도 안 바꾸고 나오면 다시 안 읽는다 — 훑던 자리를 지킨다', (tester) async {
    _phone(tester);
    final f = _fixture();
    await tester.pumpWidget(MaterialApp(home: FeedScreen(repository: f.repo)));
    await tester.pumpAndSettle();
    final loadsBefore = f.feedLoads;

    await _openDetail(tester);
    await _systemBack(tester);

    expect(f.feedLoads, loadsBefore,
        reason: '열어 보기만 해도 다시 읽으면 "더 보기" 로 쌓은 장이 사라지고 '
            '스크롤이 맨 위로 돌아간다');
  });
}

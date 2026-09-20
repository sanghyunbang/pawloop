// 이 장소의 글 — 장소 페이지. 이슈 #723(조각 2) → #729.
//
// 진짜 `CommunityRepository` 에 `MockClient`(목록 + 집계 두 경로). 여기서 재는 것.
//   - 서버에 **그 장소의 contentId** 로 목록을 묻고, 머리의 숫자 셋은 집계 API 그대로다
//   - 갈래 둘(사진 | 글) — 사진 갈래는 사진 벽, 글 갈래는 **피드와 같은 카드**(`PostCard` 의 키)
//   - 사진이 하나도 없으면 글 갈래가 먼저 열린다
//   - 정렬: 최신(기본) · 반응 많은 순 — 반응 합이 큰 글이 위로
//   - 바닥 고정 '이 장소로 글쓰기' 는 빈 화면에도 목록에도 있다
//   - 토큰이 없어도 부른다 — 글은 공개다
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/place_posts_screen.dart';

const _base = 'https://api.example.test';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
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
  required int id,
  required String title,
  bool withMedia = false,
  int help = 0,
  int cute = 0,
  String createdAt = '2026-09-01T07:30:00Z',
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'title': title,
      'body': '본문',
      'loc': '성수연방',
      'contentId': '2745594',
      'commentCount': 0,
      'reactions': {'help': help, 'cute': cute, 'empathy': 0, 'mine': null},
      'createdAt': createdAt,
      'media': withMedia
          ? [
              {
                'id': id,
                'kind': 'image',
                'url': 'https://cdn.example.test/posts/$id/1.jpg',
                'posterUrl': null,
                'width': 1600,
                'height': 1200,
                'durationMs': null,
              }
            ]
          : const [],
      'bookmarked': false,
      'dog': null,
    };

const _place = PetPlace(
  contentId: '2745594',
  title: '성수연방',
  contentTypeId: '12',
  addr: '서울 성동구 성수이로14길 14',
  image: '',
  tel: '',
  lat: 37.5417,
  lng: 127.0569,
  distM: 810,
);

class _Fixture {
  final CommunityRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);
}

_Fixture _fixture({
  List<Map<String, Object?>> feed = const [],
  Map<String, Object?> summary = const {'posts': 0, 'photos': 0, 'walks': 0},
}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/summary')) return _json(summary);
      return _json({'items': feed, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _NoTokens(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

Future<void> _pump(WidgetTester tester, _Fixture f) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: PlacePostsScreen(contentId: '2745594', title: '성수연방', place: _place, repository: f.repo),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('그 장소의 contentId 로 목록을 묻고, 머리의 숫자 셋은 집계 API 그대로다', (tester) async {
    final f = _fixture(
      feed: [_post(id: 1, title: '마당 사진', withMedia: true), _post(id: 2, title: '그늘 벤치 후기')],
      summary: {'posts': 2, 'photos': 1, 'walks': 7},
    );
    await _pump(tester, f);

    final feedReq = f.requests.singleWhere((r) => r.url.path == '/api/community/posts');
    expect(feedReq.url.queryParameters['contentId'], '2745594',
        reason: '서버가 좁혀 준다 — 전체를 받아 앱에서 거르면 첫 장에 없는 글은 영영 안 보인다');
    expect(f.requests.any((r) => r.url.path == '/api/community/places/2745594/summary'), isTrue);
    expect(find.byKey(const Key('place-posts-header')), findsOneWidget);
    expect(find.text('글 2 · 사진 1 · 산책 7회'), findsOneWidget);
    expect(find.text('서울 성동구 성수이로14길 14'), findsOneWidget, reason: '장소 머리의 주소');
  });

  testWidgets('갈래 둘 — 사진 갈래는 사진 벽, 글 갈래는 피드와 같은 카드', (tester) async {
    final f = _fixture(
      feed: [_post(id: 1, title: '마당 사진', withMedia: true), _post(id: 2, title: '그늘 벤치 후기')],
      summary: {'posts': 2, 'photos': 1, 'walks': 0},
    );
    await _pump(tester, f);

    // 사진이 있으니 사진 갈래가 먼저다.
    expect(find.byKey(const Key('place-post-2')), findsNothing);
    await tester.tap(find.byKey(const Key('place-posts-tab-posts')));
    await tester.pumpAndSettle();
    // 사진 있는 카드가 위에서 화면을 많이 먹는다 — 목록은 보이는 것만 만들어서, 둘째 카드는 내려야 나온다.
    await tester.scrollUntilVisible(find.byKey(const Key('place-post-2')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-post-2')), findsOneWidget, reason: '글 갈래는 PostCard');
    expect(find.byKey(const Key('reaction-help-2')), findsOneWidget, reason: '피드 카드의 반응 줄 그대로');
    expect(find.byKey(const Key('bookmark-2')), findsOneWidget);
  });

  testWidgets('사진이 하나도 없으면 글 갈래가 먼저 열린다', (tester) async {
    final f = _fixture(feed: [_post(id: 3, title: '글만')], summary: {'posts': 1, 'photos': 0, 'walks': 0});
    await _pump(tester, f);

    expect(find.byKey(const Key('place-post-3')), findsOneWidget);
  });

  testWidgets('정렬 — 반응 많은 순을 고르면 반응 합이 큰 글이 위로 온다', (tester) async {
    final f = _fixture(
      feed: [
        _post(id: 10, title: '최신이지만 조용한 글', createdAt: '2026-09-02T07:30:00Z'),
        _post(id: 11, title: '오래됐지만 인기 글', help: 3, cute: 2, createdAt: '2026-09-01T07:30:00Z'),
      ],
      summary: {'posts': 2, 'photos': 0, 'walks': 0},
    );
    await _pump(tester, f);

    Offset top(int id) => tester.getTopLeft(find.byKey(Key('place-post-$id')));
    expect(top(10).dy, lessThan(top(11).dy), reason: '기본은 최신 — 서버 순서 그대로');

    await tester.tap(find.byKey(const Key('place-posts-sort-reactions')));
    await tester.pumpAndSettle();
    expect(top(11).dy, lessThan(top(10).dy), reason: '반응 5 인 글이 0 인 글 위로');
  });

  testWidgets('바닥 고정 "이 장소로 글쓰기" 는 빈 화면에도 목록에도 있다', (tester) async {
    final empty = _fixture();
    await _pump(tester, empty);
    expect(find.byKey(const Key('place-posts-write')), findsOneWidget);
    expect(find.byKey(const Key('place-posts-empty')), findsOneWidget, reason: '사진이 없으니 글 갈래의 빈 상태');
    expect(find.text('아직 이 장소의 글이 없어요'), findsOneWidget);

    final some = _fixture(feed: [_post(id: 4, title: '글')], summary: {'posts': 1, 'photos': 0, 'walks': 0});
    await _pump(tester, some);
    expect(find.byKey(const Key('place-posts-write')), findsOneWidget);
  });

  testWidgets('토큰이 없어도(게스트) 서버를 부른다 — 글은 공개다', (tester) async {
    final f = _fixture(feed: [_post(id: 5, title: '게스트도 본다')], summary: {'posts': 1, 'photos': 0, 'walks': 0});
    await _pump(tester, f);

    expect(f.requests.map((r) => r.url.path).toSet(),
        {'/api/community/posts', '/api/community/places/2745594/summary'});
    expect(find.byKey(const Key('place-post-5')), findsOneWidget);
  });
}

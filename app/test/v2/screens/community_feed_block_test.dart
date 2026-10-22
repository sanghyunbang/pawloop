// 차단한 사람의 글은 커뮤니티 글 목록 **어디에도** 없다 — 애플 지침 1.2 ("피드에서 즉시 사라져야 한다").
//
// ## 접기에서 빼기로
//
// 2026-09-18 에 "상세에는 가리기가 나오는데 기본 화면에서 보면 그대로 노출된다" 고 알게 되어
// 목록이 서버의 `hiddenByBlock` 을 보고 **접게** 했다("가린 사람의 글입니다 · 눌러서 보기"). App Store
// 심사가 1.2 로 반려하며 요구한 것은 접힌 자리가 아니라 **사라지는 것**이다. 그래서 카드 · 목록 · 사진
// 벽에서 접힌 자리도 없이 뺀다.
//
// ## 어디서 재나 — 커뮤니티 글 목록을 그리는 자리 전부
//
// 피드(카드 · 목록 · 사진 벽) · 장소의 글(사진 · 글 갈래) · 저장한 글 · 아이 사진첩 · 홈의 이웃 사진.
// 한 자리만 빠뜨려도 차단한 사람의 사진이 그 화면에서 크게 보인다 — 2026-10 전에는 장소의 사진 벽 ·
// 저장한 글 · 아이 사진첩 · 이웃 사진이 실제로 표시를 안 보고 있었다.
//
// 서버가 지금은 차단한 사람의 글을 목록에 안 보내지만(서버 PR), **옛 서버는 표시를 붙여 보낸다.** 앱이
// 그 표시로도 빼야 서버가 늦게 나가도 1.2 가 지켜진다. 그래서 여기 가짜 서버는 옛 서버처럼
// `hiddenByBlock: true` 를 붙여 보낸다. 차단한 순간 다시 부르지 않고 빠지는 것은
// `community_block_action_test.dart` 가 잰다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/blocked_authors.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/dog_gallery_screen.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/place_posts_screen.dart';
import 'package:heat_trip_flutter/v2/screens/saved_posts_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/neighbor_photo_strip.dart';
import 'package:heat_trip_flutter/v2/widgets/post_photo_wall.dart';

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

Map<String, Object?> _media(int id) => {
      'id': id,
      'kind': 'image',
      'url': 'https://cdn.example.test/posts/7/$id.jpg',
      'posterUrl': null,
      'width': 1600,
      'height': 1200,
      'durationMs': null,
    };

/// 계약의 `Post`. 제목에 글 번호를 넣어 어느 글이 남았는지 글자로 가른다.
Map<String, Object?> _post({
  int id = 12,
  required bool hidden,
  List<Map<String, Object?>> media = const [],
}) =>
    {
      'id': id,
      'author': {'userId': hidden ? 99 : 7, 'nickname': hidden ? '차단한사람' : '보리아빠'},
      'board': 'walk_review',
      'loc': '서울숲',
      'contentId': '126508',
      'title': '글 $id 제목',
      'body': '글 $id 본문',
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': media,
      'bookmarked': true,
      'dog': {'id': 7, 'name': '보리', 'avatarUrl': null},
      'hiddenByBlock': hidden,
    };

CommunityRepository _repo(List<Map<String, Object?>> items, {bool hasMore = false}) {
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path.endsWith('/summary')) {
        return _json({'posts': items.length, 'photos': 0, 'walks': 0});
      }
      return _json({'items': items, 'nextCursor': hasMore ? 'NEXT' : null, 'hasMore': hasMore});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return CommunityRepository(baseUrl: _base, client: client);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

final _strip = find.byKey(const Key('post-media-strip'));

void main() {
  setUp(() {
    BlockedAuthors.clear();
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.authenticated;
  });
  tearDown(() {
    BlockedAuthors.clear();
    AuthState.resetForTest();
  });

  // ─────────────────── 피드 ───────────────────

  testWidgets('차단한 사람의 글은 카드 목록에 아예 없다 — 접힌 자리도 "눌러서 보기" 도 없다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(id: 12, hidden: true), _post(id: 13, hidden: false)])));

    expect(find.text('글 12 제목'), findsNothing);
    expect(find.text('글 12 본문'), findsNothing);
    expect(find.textContaining('눌러서 보기'), findsNothing, reason: '''
애플 지침 1.2 — 차단한 사람의 콘텐츠는 피드에서 사라져야 한다. 접힌 자리를 남기면 사라진 것이 아니다.''');
    expect(find.textContaining('가린 사람'), findsNothing);
    expect(find.text('글 13 제목'), findsOneWidget, reason: '''
차단은 사람 단위이지 목록 단위가 아니다 — 한 사람을 차단했다고 남의 글까지 빼면 안 된다.''');
  });

  testWidgets('차단한 사람의 사진도 안 그린다 — 가장 불쾌할 수 있는 것이 사진이다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(hidden: true, media: [_media(1)])])));

    expect(_strip, findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('차단하지 않은 글은 그대로 보인다 — 이 검사가 없으면 전부 숨겨도 초록이다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(hidden: false, media: [_media(1)])])));

    expect(find.text('글 12 제목'), findsOneWidget);
    expect(_strip, findsOneWidget, reason: '차단하지 않은 글의 사진은 그대로 그린다');
  });

  testWidgets('목록형 보기에서도 빠진다 — 보기를 바꾸면 새는 자리가 없어야 한다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(id: 12, hidden: true, media: [_media(1)]), _post(id: 13, hidden: false)])));

    await tester.tap(find.byKey(const Key('feed-view-list')));
    await tester.pumpAndSettle();

    expect(find.text('글 12 제목'), findsNothing, reason: '''
카드형만 막고 목록형을 두면, 보기를 한 번 바꾸는 것으로 차단이 풀린다.''');
    expect(find.byKey(const Key('post-thumb-12')), findsNothing);
    expect(find.text('글 13 제목'), findsOneWidget);
  });

  testWidgets('사진 벽에는 차단한 사람의 사진이 아예 안 걸린다 — 여기가 가장 위험하다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(hidden: true, media: [_media(1)])])));

    await tester.tap(find.byKey(const Key('feed-view-grid')));
    await tester.pumpAndSettle();

    expect(find.byType(PostPhotoWall), findsNothing, reason: '''
사진 벽은 사진만 모아 크게 건다. 사진이 있는 글이 차단한 사람의 것뿐이라면 벽에 걸 것이 없다.''');
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('사진 벽이 섞여 있으면 차단한 것만 빠진다 — 벽에 넘기는 목록을 직접 본다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([
      _post(id: 12, hidden: true, media: [_media(1)]),
      _post(id: 13, hidden: false, media: [_media(2)]),
    ])));

    await tester.tap(find.byKey(const Key('feed-view-grid')));
    await tester.pumpAndSettle();

    expect(find.byType(PostPhotoWall), findsOneWidget, reason: '''
이 검사가 없으면 벽을 통째로 꺼 버려도 아래 검사가 초록이다.''');
    // 섞여 있을 때 벽에 실제로 넘어가는 목록을 봐야 "벽에 전부 넘긴다" 로 되돌린 것이 잡힌다 —
    // 차단한 글 하나만 두면 벽 자체가 안 서서 무엇을 넘기든 초록이었다.
    final wall = tester.widget<PostPhotoWall>(find.byType(PostPhotoWall));
    expect(wall.posts.map((p) => p.id), isNot(contains(12)));
    expect(wall.posts.map((p) => p.id), contains(13));
  });

  testWidgets('"N개의 글" 은 차단한 사람의 글을 세지 않는다 — 보이는 글과 수가 같아야 한다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([
      _post(id: 12, hidden: true),
      _post(id: 13, hidden: false),
      _post(id: 14, hidden: false),
    ])));

    expect(find.text('2개의 글'), findsOneWidget);
    expect(find.text('3개의 글'), findsNothing);
  });

  testWidgets('받은 글이 전부 차단한 사람의 것이고 다음 장이 없으면 "아직 글이 없어요" 다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(hidden: true)])));

    expect(find.text('아직 글이 없어요'), findsOneWidget);
  });

  testWidgets('받은 글이 전부 차단한 사람의 것이어도 다음 장이 있으면 "더 보기" 가 남는다', (tester) async {
    _phone(tester);
    await _open(tester, FeedScreen(repository: _repo([_post(hidden: true)], hasMore: true)));

    expect(find.text('아직 글이 없어요'), findsNothing, reason: '''
옛 서버는 차단한 사람의 글을 한 장에 섞어 보낸다 — 그 장이 전부 빠졌다고 "글이 없다" 고 하면 다음 장을 못 연다.''');
    expect(find.text('더 보기'), findsOneWidget);
  });

  // ─────────────────── 피드 밖의 목록들 ───────────────────

  testWidgets('장소의 글 — 사진 갈래에도 글 갈래에도 차단한 사람의 글이 없다', (tester) async {
    _phone(tester);
    await _open(tester, PlacePostsScreen(
      contentId: '126508',
      title: '서울숲',
      repository: _repo([
        _post(id: 12, hidden: true, media: [_media(1)]),
        _post(id: 13, hidden: false, media: [_media(2)]),
      ]),
    ));

    final wall = tester.widget<PostPhotoWall>(find.byType(PostPhotoWall));
    expect(wall.posts.map((p) => p.id), [13], reason: '사진 갈래가 먼저 열린다 — 거기 차단한 사람의 사진이 걸리면 안 된다');

    await tester.tap(find.byKey(const Key('place-posts-tab-posts')));
    await tester.pumpAndSettle();
    expect(find.text('글 12 제목'), findsNothing);
    expect(find.text('글 13 제목'), findsOneWidget);

    await tester.tap(find.byKey(const Key('place-posts-sort-reactions')));
    await tester.pumpAndSettle();
    expect(find.text('글 12 제목'), findsNothing, reason: '정렬을 바꿔도 새지 않는다');
  });

  testWidgets('저장한 글 — 저장해 둔 글이라도 차단한 사람의 것은 없다', (tester) async {
    _phone(tester);
    await _open(tester, SavedPostsScreen(repository: _repo([
      _post(id: 12, hidden: true, media: [_media(1)]),
      _post(id: 14, hidden: true),
      _post(id: 13, hidden: false, media: [_media(2)]),
    ])));

    final wall = tester.widget<PostPhotoWall>(find.byType(PostPhotoWall));
    expect(wall.posts.map((p) => p.id), [13]);
    expect(find.byKey(const Key('saved-row-14')), findsNothing, reason: '사진 없는 글 줄에도 없다');
  });

  testWidgets('아이 사진첩 — 우리 아이를 찍은 글이라도 차단한 사람의 것은 없다', (tester) async {
    _phone(tester);
    const bori = DogProfile(serverId: 7, name: '보리', breed: '', size: DogSize.small, ageMonths: 30);
    await _open(tester, DogGalleryScreen(dog: bori, repository: _repo([
      _post(id: 12, hidden: true, media: [_media(1)]),
      _post(id: 14, hidden: true),
      _post(id: 13, hidden: false, media: [_media(2)]),
    ])));

    final wall = tester.widget<PostPhotoWall>(find.byType(PostPhotoWall));
    expect(wall.posts.map((p) => p.id), [13]);
    expect(find.byKey(const Key('gallery-row-14')), findsNothing);
  });

  testWidgets('홈의 이웃 사진 — 차단한 사람의 사진은 줄에 안 걸린다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NeighborPhotoStrip(repository: _repo([
            _post(id: 12, hidden: true, media: [_media(1)]),
            _post(id: 13, hidden: false, media: [_media(2)]),
          ])),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-strip-12')), findsNothing);
    expect(find.byKey(const Key('photo-strip-13')), findsOneWidget);
  });

  testWidgets('홈의 이웃 사진이 전부 차단한 사람의 것이면 줄 자체가 없다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NeighborPhotoStrip(repository: _repo([_post(id: 12, hidden: true, media: [_media(1)])])),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('neighbor-photo-strip')), findsNothing);
  });
}

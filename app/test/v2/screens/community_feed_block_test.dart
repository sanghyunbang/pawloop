// 가린 사람의 글은 **커뮤니티 목록에서도** 접힌다 (#166 · 1.2).
//
// **여기가 비어 있었다.** 서버는 읽는 사람 기준으로 `hiddenByBlock` 을 계산해 붙여 보내는데
// (`community_repository.dart:360`), 그 값을 보는 화면이 글 상세(`post_detail_screen.dart:802`)와
// 채팅(`family_chat_screen.dart:1104`)뿐이었다. 목록은 그대로 그렸다 — **가리기를 눌러도 피드에서는
// 아무것도 달라지지 않았다.** 2026-09-18 에 사장님이 실기기에서 "상세에는 가리기가 나오는데 기본
// 화면에서 보면 그대로 노출된다" 고 알려 주셨다.
//
// 애플 지침 1.2 가 요구하는 "불쾌한 사용자를 차단하는 수단" 이 이것이다. 심사자가 영상에서 차단하는
// 장면을 보고 직접 눌러 봤다가 목록에 그대로 있으면, 차단이 동작하지 않는다고 판단한다.
//
// `community_feed_media_test.dart` 와 같은 방식 — 진짜 `CommunityRepository` 에 `MockClient`.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/post_photo_wall.dart';

const _base = 'https://api.example.test';

const _title = '서울숲 아침 산책 코스 추천';
const _body = '이른 아침엔 사람이 적어서 대형견도 편해요.';

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

Map<String, Object?> _post({
  int id = 12,
  required bool hidden,
  List<Map<String, Object?>> media = const [],
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'loc': '서울숲',
      'contentId': '126508',
      'title': _title,
      'body': _body,
      'commentCount': 1,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': media,
      'hiddenByBlock': hidden,
    };

CommunityRepository _repo(List<Map<String, Object?>> items) {
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      if (RegExp(r'^/api/community/posts/\d+$').hasMatch(request.url.path)) {
        return _json(items.first);
      }
      return _json({'items': items, 'nextCursor': null, 'hasMore': false});
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

Future<void> _open(WidgetTester tester, CommunityRepository repo) async {
  await tester.pumpWidget(MaterialApp(home: FeedScreen(repository: repo)));
  await tester.pumpAndSettle();
}

final _strip = find.byKey(const Key('post-media-strip'));

void main() {
  testWidgets('가린 사람의 글은 목록에서 제목도 본문도 안 보인다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: true)]));

    expect(find.text(_title), findsNothing, reason: '''
제목만 남기면 거기에 욕을 적으면 그만이다. 가린 사람의 글은 제목도 안 보여야 한다.''');
    expect(find.text(_body), findsNothing);
    expect(find.text('가린 사람의 글입니다 · 눌러서 보기'), findsOneWidget, reason: '''
아무것도 안 그리면 사용자는 가리기가 먹혔는지 알 수 없다. 자리를 남기되 내용을 접는다.''');
  });

  testWidgets('가린 사람의 글은 사진도 안 그린다 — 가장 불쾌할 수 있는 것이 사진이다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: true, media: [_media(1)])]));

    expect(_strip, findsNothing, reason: '''
글자만 접고 사진을 남기면 차단이 아무 일도 안 한 것과 같다 — 사람들은 사진을 먼저 본다.''');
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('가리지 않은 글은 그대로 보인다 — 이 검사가 없으면 전부 숨겨도 초록이다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: false, media: [_media(1)])]));

    expect(find.text(_title), findsOneWidget);
    expect(_strip, findsOneWidget, reason: '가리지 않은 글의 사진은 그대로 그린다');
    expect(find.text('가린 사람의 글입니다 · 눌러서 보기'), findsNothing);
  });

  testWidgets('섞여 있으면 가린 것만 접힌다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([
      _post(id: 12, hidden: true, media: [_media(1)]),
      _post(id: 13, hidden: false),
    ]));

    expect(find.byKey(const Key('blocked-post-12')), findsOneWidget);
    expect(find.byKey(const Key('blocked-post-13')), findsNothing, reason: '''
가리기는 사람 단위이지 목록 단위가 아니다. 한 사람을 가렸다고 남의 글까지 접으면 안 된다.''');
    expect(find.text(_title), findsOneWidget, reason: '가리지 않은 쪽 제목은 남는다');
  });

  testWidgets('목록형 보기에서도 접힌다 — 보기를 바꾸면 새는 자리가 없어야 한다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: true, media: [_media(1)])]));

    await tester.tap(find.byKey(const Key('feed-view-list')));
    await tester.pumpAndSettle();

    expect(find.text(_title), findsNothing, reason: '''
카드형만 막고 목록형을 두면, 보기를 한 번 바꾸는 것으로 차단이 풀린다.''');
    expect(find.text('가린 사람의 글입니다 · 눌러서 보기'), findsOneWidget);
    expect(_strip, findsNothing);
  });

  testWidgets('사진 벽에는 가린 사람의 사진이 아예 안 걸린다 — 여기가 가장 위험하다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: true, media: [_media(1)])]));

    await tester.tap(find.byKey(const Key('feed-view-grid')));
    await tester.pumpAndSettle();

    expect(find.byType(PostPhotoWall), findsNothing, reason: '''
사진 벽은 사진만 모아 크게 건다. 사진이 있는 글이 가린 사람의 것뿐이라면 벽에 걸 것이 없다 —
접힌 칸을 끼우는 것도 답이 아니다(벽이 구멍난 것처럼 보인다).''');
    expect(find.byType(Image), findsNothing, reason: '''
카드·목록만 막고 벽을 두면, 차단한 사람의 사진이 **가장 크게** 보이는 화면이 남는다.''');
  });

  testWidgets('사진 벽이 섞여 있으면 가린 것만 빠진다 — 벽에 넘기는 목록을 직접 본다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([
      _post(id: 12, hidden: true, media: [_media(1)]),
      _post(id: 13, hidden: false, media: [_media(2)]),
    ]));

    await tester.tap(find.byKey(const Key('feed-view-grid')));
    await tester.pumpAndSettle();

    expect(find.byType(PostPhotoWall), findsOneWidget, reason: '''
이 검사가 없으면 벽을 통째로 꺼 버려도 아래 검사가 초록이다.''');

    // **되돌리기 증명이 잡아낸 자리다.** 처음에는 "가린 글 하나만" 넣고 벽이 안 그려지는 것을
    // 봤는데, 그때는 `withMedia(visible)` 이 비어서 벽 자체가 안 서기 때문에 `posts:` 에
    // 무엇을 넘기든 초록이었다 — 사진 벽을 예전 코드(`posts: _posts`)로 되돌려도 안 빨개졌다.
    // **섞여 있을 때** 벽에 실제로 넘어가는 목록을 봐야 그 되돌림이 잡힌다.
    final wall = tester.widget<PostPhotoWall>(find.byType(PostPhotoWall));
    expect(wall.posts.map((p) => p.id), isNot(contains(12)), reason: '''
가린 사람의 글이 벽에 넘어가면 그 사진이 크게 걸린다. 벽이 서 있는지만 보면 이걸 못 잡는다.''');
    expect(wall.posts.map((p) => p.id), contains(13), reason: '''
가리지 않은 글은 그대로 걸려야 한다 — 이 줄이 없으면 벽에 빈 목록을 넘겨도 위가 초록이다.''');
  });

  testWidgets('접힌 카드를 눌러도 글은 열린다 — 상세에서 펼 수 있다', (tester) async {
    _phone(tester);
    await _open(tester, _repo([_post(hidden: true)]));

    await tester.tap(find.byKey(const Key('blocked-post-12')));
    await tester.pumpAndSettle();

    expect(find.text('가린 사람의 글입니다 · 눌러서 보기'), findsNothing, reason: '''
목록에서는 펴지 않는다 — 탭은 글을 여는 동작이다. 펴는 것은 상세의 몫이고(#166),
그래서 여기서는 상세로 넘어간 것만 확인한다.''');
    expect(find.text('가린 사람의 글입니다. 눌러서 보기'), findsOneWidget, reason: '''
상세의 문구다(`post_detail_screen.dart:465`). 거기서는 눌러서 펼 수 있다.''');
  });
}

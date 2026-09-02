// 앱이 읽는 키가 서버가 주는 키와 같은가 — 커뮤니티판 (이슈 #171).
//
// ## 왜 이 파일이 따로 있는가
//
// 채팅에서 메시지 목록의 키를 한동안 `messages` 로 읽었다. 서버는 `items` 를 준다.
// 그래서 실기기에서 대화가 **언제나 비어 보였다.** 그런데 테스트는 초록불이었다 —
// `MockClient` 가 `messages` 로 응답을 흉내 냈기 때문이다(#82).
//
// **서버를 잘못 흉내 낸 테스트는 아무것도 지키지 못한다.** 그래서 여기서는 응답에
// **계약의 키만** 넣는다. 앱이 다른 키를 읽으면 값을 못 찾아 빨간불이 된다.
//
// 커뮤니티에는 채팅에 없던 자리가 하나 더 있다 — `reactions.mine` 의 **`null` 과 `[]`**.
// 게스트에게는 `null` 이고 로그인했는데 안 누른 사람에게는 `[]` 다. 둘을 뭉개면
// 게스트 화면에 "안 눌렀음" 하이라이트가 그려지고, 눌렀을 때 401 이 난다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';

const _base = 'https://api.test';

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

CommunityRepository _repo(MockClient inner, {String? token = 'AT-1'}) =>
    CommunityRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: inner,
        baseUrl: _base,
        store: _FakeTokenStore(token),
      ),
    );

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 계약의 `Post` 한 건. 키 이름을 여기서 한 벌만 적는다.
Map<String, Object?> _post({Object? mine = const <String>[]}) => {
      'id': 12,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'walk_review',
      'loc': '서울숲',
      'contentId': '126508',
      'title': '서울숲 아침 산책 코스 추천',
      'body': '이른 아침엔 사람이 적어서 대형견도 편해요.',
      'commentCount': 4,
      'reactions': {'help': 7, 'cute': 3, 'empathy': 2, 'mine': mine},
      'createdAt': '2026-09-01T07:30:00Z',
    };

void main() {
  test('글 목록의 키는 items 다 — posts 를 읽으면 목록이 언제나 빈다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [_post()],
          'nextCursor': 'MTc1NjcwMDIwMDow',
          'hasMore': true,
        })));

    final page = await repo.feed();

    expect(page.items, hasLength(1),
        reason: '이 단언이 깨졌다면 앱이 items 가 아닌 다른 키를 읽고 있다');
    expect(page.items.single.title, '서울숲 아침 산책 코스 추천');
    expect(page.nextCursor, 'MTc1NjcwMDIwMDow');
    expect(page.hasMore, isTrue);
  });

  test('board 는 ASCII 키로 나가고 한글은 화면 문구로만 쓴다', () async {
    Uri? seen;
    final repo = _repo(MockClient((request) async {
      seen = request.url;
      return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
    }));

    await repo.feed(board: CommunityBoard.walkReview);

    expect(seen?.queryParameters['board'], 'walk_review',
        reason: 'ADR-0016 이 정한 값이다. 한글이 나가면 서버가 400 으로 거절한다');
    expect(CommunityBoard.walkReview.label, '산책로 후기');
  });

  test('author 는 PersonRef 다 — userId 가 없으면 내 글인지 판별할 수 없다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        })));

    final author = (await repo.feed()).items.single.author;

    expect(author.userId, 7);
    expect(author.nickname, '보리아빠');
    expect(author.isWithdrawn, isFalse);
  });

  test('탈퇴한 사람의 글은 userId 0 · 알 수 없음 으로 온다 — 글은 남는다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [
            {..._post(), 'author': {'userId': 0, 'nickname': '알 수 없음'}},
          ],
          'nextCursor': null,
          'hasMore': false,
        })));

    final author = (await repo.feed()).items.single.author;

    expect(author.isWithdrawn, isTrue);
    expect(author.nickname, '알 수 없음');
  });

  test('mine 이 null 이면 게스트다 — 빈 배열(로그인·안 누름)과 다르다', () async {
    final guest = _repo(
      MockClient((_) async => _json({
            'items': [_post(mine: null)],
            'nextCursor': null,
            'hasMore': false,
          })),
      token: null,
    );

    final reactions = (await guest.feed()).items.single.reactions;

    expect(reactions.mine, isNull);
    expect(reactions.isMine(CommunityReaction.help), isFalse,
        reason: '게스트에게 하이라이트를 그리면 눌렀을 때 401 이 난다');
    expect(reactions.help, 7, reason: '집계는 게스트에게도 보인다');
  });

  test('mine 에 담긴 것들이 켜진 반응이다 — 셋을 동시에 누를 수 있다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [
            _post(mine: const ['help', 'empathy']),
          ],
          'nextCursor': null,
          'hasMore': false,
        })));

    final reactions = (await repo.feed()).items.single.reactions;

    expect(reactions.isMine(CommunityReaction.help), isTrue);
    expect(reactions.isMine(CommunityReaction.empathy), isTrue);
    expect(reactions.isMine(CommunityReaction.cute), isFalse);
  });

  test('장소 키는 contentId 다 — placeId 는 ADR-0017 이 없앤 이름이다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [_post()],
          'nextCursor': null,
          'hasMore': false,
        })));

    expect((await repo.feed()).items.single.contentId, '126508',
        reason: 'Place 조회의 contentId 와 같은 키여야 장소 단위로 이어 붙일 수 있다');
  });

  test('댓글 목록도 items 다', () async {
    final repo = _repo(MockClient((_) async => _json({
          'items': [
            {
              'id': 3,
              'author': {'userId': 9, 'nickname': '초코맘'},
              'body': '코스 정보 감사해요!',
              'createdAt': '2026-09-01T08:00:00Z',
            },
          ],
          'nextCursor': null,
          'hasMore': false,
        })));

    final page = await repo.comments(12);

    expect(page.items.single.body, '코스 정보 감사해요!');
    expect(page.items.single.author.userId, 9);
  });

  test('반응은 멱등한 POST·DELETE 둘이다 — 경로에 종류가 들어간다', () async {
    final calls = <String>[];
    final repo = _repo(MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      return _json({'help': 8, 'cute': 3, 'empathy': 2, 'mine': const ['help']});
    }));

    final summary = await repo.addReaction(12, CommunityReaction.help);
    await repo.removeReaction(12, CommunityReaction.cute);

    expect(calls, [
      'POST /api/community/posts/12/reactions/help',
      'DELETE /api/community/posts/12/reactions/cute',
    ]);
    expect(summary.help, 8, reason: '응답의 집계를 그대로 쓴다 — 로컬에서 세지 않는다');
    expect(summary.isMine(CommunityReaction.help), isTrue);
  });

  test('글쓰기는 board 를 wire 값으로 싣는다', () async {
    Map<String, Object?>? sent;
    final repo = _repo(MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, Object?>;
      return _json(_post(), status: 201);
    }));

    await repo.createPost(
      board: CommunityBoard.petPlace,
      title: '성수동 카페',
      body: '동반 가능해요',
      contentId: '126508',
    );

    expect(sent?['board'], 'pet_place');
    expect(sent?['contentId'], '126508');
    expect(sent?.containsKey('loc'), isFalse, reason: '빈 값은 아예 안 보낸다');
  });

  test('401 은 unauthorized 로, 429 는 rateLimited 로 갈린다 — 문구가 다르다', () async {
    final unauthorized = _repo(MockClient((_) async => _json({}, status: 401)));
    final limited = _repo(MockClient((_) async => _json({}, status: 429)));

    await expectLater(
      unauthorized.addComment(12, '안녕하세요'),
      throwsA(isA<CommunityFailure>().having(
          (failure) => failure.kind, 'kind', CommunityFailureKind.unauthorized)),
    );
    await expectLater(
      limited.addComment(12, '안녕하세요'),
      throwsA(isA<CommunityFailure>().having(
          (failure) => failure.kind, 'kind', CommunityFailureKind.rateLimited)),
    );
  });

  test('charset 이 없는 응답도 한글이 안 깨진다 — bodyBytes 로 읽는다', () async {
    // #81 에서 실제로 깨진 자리다. `res.body` 는 charset 이 없으면 latin-1 로 읽는다.
    final repo = _repo(MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [_post()],
            'nextCursor': null,
            'hasMore': false,
          })),
          200,
          headers: const {'content-type': 'application/json'},
        )));

    expect((await repo.feed()).items.single.author.nickname, '보리아빠');
  });
}

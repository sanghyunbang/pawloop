// 글에 찍힌 아이 · 아이 사진첩 — 이슈 #451 (5번).
//
// 글쓰기의 "어떤 아이?" 칩이 dogId 를 싣고, 카드에는 아이 꼬리표가 붙고, 내 정보의 아이 머리 아래
// "○○의 사진첩" 이 그 아이의 글(?dogId=)을 사진 벽으로 모은다.
//
// 진짜 `CommunityRepository` 에 `MockClient`. 응답에는 계약의 키만(`dog: {id, name, avatarUrl}`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/dog_gallery_screen.dart';
import 'package:heat_trip_flutter/v2/screens/feed_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_detail_screen.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

import '../support/fake_media_picker.dart';

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
  String title = '보리 사진',
  Map<String, Object?>? dog,
  bool withMedia = true,
}) =>
    {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'brag',
      'title': title,
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': withMedia ? [_media(id)] : const [],
      'bookmarked': false,
      'dog': dog,
    };

const _boriTag = {'id': 7, 'name': '보리', 'avatarUrl': 'https://cdn.example.test/profiles/1/bori.jpg'};

class _Fixture {
  final CommunityRepository repo;
  final List<http.Request> requests;
  _Fixture(this.repo, this.requests);
}

_Fixture _fixture({List<Map<String, Object?>> feed = const []}) {
  final requests = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/community/posts') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_post(id: 99, title: body['title'] as String,
            dog: body['dogId'] == 7 ? _boriTag : (body['dogId'] == 8 ? {'id': 8, 'name': '탄이', 'avatarUrl': null} : null),
            withMedia: false), status: 201);
      }
      if (request.method == 'PATCH' && path.startsWith('/api/community/posts/')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_post(id: 12, dog: body['dogId'] == 8 ? {'id': 8, 'name': '탄이', 'avatarUrl': null} : _boriTag, withMedia: false));
      }
      if (path.endsWith('/comments')) {
        return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
      }
      if (RegExp(r'^/api/community/posts/\d+$').hasMatch(path)) {
        return _json(feed.first);
      }
      return _json({'items': feed, 'nextCursor': null, 'hasMore': false});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return _Fixture(CommunityRepository(baseUrl: _base, client: client), requests);
}

const _bori = DogProfile(serverId: 7, name: '보리', breed: '', size: DogSize.small, ageMonths: 30);
const _tan = DogProfile(serverId: 8, name: '탄이', breed: '', size: DogSize.medium, ageMonths: 12);

Widget _host(Widget child) => MaterialApp(home: child);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.authenticated;
    replacePets(const [_bori, _tan]);
    selectPet(0);
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  group('저장소 — 계약의 키', () {
    test('feed 는 dogId 를 쿼리로, createPost·updatePost 는 본문으로 싣고, 응답의 dog 를 읽는다', () async {
      final f = _fixture(feed: [_post(dog: _boriTag)]);

      final page = await f.repo.feed(dogId: 7, limit: 30);
      expect(f.requests.last.url.queryParameters['dogId'], '7');
      expect(page.items.single.dog?.name, '보리');
      expect(page.items.single.dog?.avatarUrl, _boriTag['avatarUrl']);

      final created = await f.repo.createPost(board: CommunityBoard.brag, title: '글', body: '본문', dogId: 7);
      expect(jsonDecode(f.requests.last.body)['dogId'], 7);
      expect(created.dog?.id, 7);

      await f.repo.createPost(board: CommunityBoard.brag, title: '글', body: '본문');
      expect((jsonDecode(f.requests.last.body) as Map).containsKey('dogId'), isFalse, reason: '안 골랐으면 키가 없다');

      final patched = await f.repo.updatePost(12, dogId: 8);
      expect(jsonDecode(f.requests.last.body), {'dogId': 8});
      expect(patched?.dog?.name, '탄이');

      expect(CommunityPost.tryParse(_post(dog: null))!.dog, isNull);
    });
  });

  group('글쓰기 — 어떤 아이?', () {
    Future<_Fixture> pumpWrite(WidgetTester tester, {CommunityPost? editing}) async {
      _phone(tester);
      final f = _fixture();
      await tester.pumpWidget(_host(PostWriteScreen(
        repository: f.repo,
        picker: FakeMediaPicker((_) => const []),
        editing: editing,
      )));
      await tester.pumpAndSettle();
      return f;
    }

    Future<void> submit(WidgetTester tester, String label) async {
      await tester.enterText(find.byType(TextField).at(0), '제목');
      await tester.enterText(find.byType(TextField).at(1), '본문입니다');
      await tester.dragUntilVisible(find.text(label), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('내 아이가 칩으로 뜨고, 새 글은 지금 고른 아이가 기본이라 그 dogId 를 싣는다', (tester) async {
      final f = await pumpWrite(tester);

      expect(find.byKey(const Key('write-dog-7')), findsOneWidget);
      expect(find.byKey(const Key('write-dog-8')), findsOneWidget);

      await submit(tester, '올리기');

      final sent = jsonDecode(f.requests.last.body) as Map;
      expect(sent['dogId'], 7, reason: '홈에서 고른 아이(보리)가 기본이다');
    });

    testWidgets('다른 아이를 누르면 그 아이, 고른 아이를 다시 누르면 뺀다 — 아이 없는 글도 된다', (tester) async {
      final f = await pumpWrite(tester);

      await tester.tap(find.byKey(const Key('write-dog-8')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('write-dog-8')));
      await tester.pump();
      await submit(tester, '올리기');

      expect((jsonDecode(f.requests.last.body) as Map).containsKey('dogId'), isFalse);
    });

    testWidgets('아이가 없으면 줄 자체가 없다', (tester) async {
      replacePets(const []);
      await pumpWrite(tester);

      expect(find.text('어떤 아이?'), findsNothing);
      expect(find.byKey(const Key('write-dog-7')), findsNothing);
    });

    testWidgets('고치기는 원래 아이로 시작하고, 바꾸면 dogId 만 보낸다 — 비우는 길은 없다', (tester) async {
      final original = CommunityPost.tryParse(_post(id: 12, dog: _boriTag, withMedia: false))!;
      final f = await pumpWrite(tester, editing: original);

      await tester.tap(find.byKey(const Key('write-dog-7')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('write-dog-8')));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), original.title);
      await tester.enterText(find.byType(TextField).at(1), original.body);
      await tester.dragUntilVisible(find.text('고치기'), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text('고치기'));
      await tester.pumpAndSettle();

      final patch = f.requests.last;
      expect(patch.method, 'PATCH');
      expect(jsonDecode(patch.body), {'dogId': 8}, reason: '아이만 바꿨으니 dogId 만');
    });
  });

  group('카드', () {
    testWidgets('아이가 있는 글에는 게시판 칩 옆에 아이 꼬리표, 없으면 없다', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [_post(id: 12, dog: _boriTag), _post(id: 13, title: '아이 없음', dog: null)]);
      await tester.pumpWidget(_host(FeedScreen(repository: f.repo)));
      await tester.pumpAndSettle();

      final tag = find.byKey(const Key('post-dog-7'));
      expect(tag, findsOneWidget);
      expect(find.descendant(of: tag, matching: find.text('보리')), findsOneWidget);
      expect(find.byKey(const Key('post-dog-8')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('아이 사진첩', () {
    testWidgets('그 아이의 글만 ?dogId= 로 받아 사진 벽과 한 줄로 그리고, 타일은 상세로 간다', (tester) async {
      _phone(tester);
      final f = _fixture(feed: [
        _post(id: 31, dog: _boriTag),
        _post(id: 32, title: '글만', dog: _boriTag, withMedia: false),
      ]);
      await tester.pumpWidget(_host(DogGalleryScreen(dog: _bori, repository: f.repo)));
      await tester.pumpAndSettle();

      expect(f.requests.single.url.queryParameters['dogId'], '7');
      expect(find.text('보리의 사진첩'), findsOneWidget);
      expect(find.byKey(const Key('photo-tile-31')), findsOneWidget);
      expect(find.byKey(const Key('gallery-row-32')), findsOneWidget);

      await tester.tap(find.byKey(const Key('photo-tile-31')));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
    });

    testWidgets('글이 없으면 글쓰기에서 아이를 고르라고 말한다 · 서버에 없는 아이는 부르지 않는다', (tester) async {
      _phone(tester);
      final f = _fixture();
      await tester.pumpWidget(_host(DogGalleryScreen(dog: _bori, repository: f.repo)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gallery-empty')), findsOneWidget);
      expect(find.textContaining('어떤 아이?'), findsOneWidget);

      final local = _fixture();
      await tester.pumpWidget(_host(DogGalleryScreen(
          key: const Key('local'),
          dog: const DogProfile(name: '임시', breed: '', size: DogSize.small, ageMonths: 1),
          repository: local.repo)));
      await tester.pumpAndSettle();
      expect(local.requests, isEmpty);
      expect(find.byKey(const Key('gallery-empty')), findsOneWidget);
    });

    testWidgets('게스트면 서버를 안 부르고 안내다', (tester) async {
      _phone(tester);
      AuthState.status.value = AuthStatus.unauthenticated;
      final f = _fixture(feed: [_post(id: 31, dog: _boriTag)]);
      await tester.pumpWidget(_host(DogGalleryScreen(dog: _bori, repository: f.repo)));
      await tester.pumpAndSettle();

      expect(f.requests, isEmpty);
      expect(find.textContaining('로그인하면'), findsOneWidget);
    });
  });
}

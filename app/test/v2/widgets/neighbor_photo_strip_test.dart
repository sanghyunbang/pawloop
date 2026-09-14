// 홈의 "이웃의 사진" 한 줄 — 이슈 #451 (6번).
//
// 사진 있는 글만 · 열두 개까지 · 없거나 못 불러오면 줄이 없다 · 타일은 글로, 더 보기는 벽으로.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/neighbor_photo_strip.dart';

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

Map<String, Object?> _media(int id, {String kind = 'image'}) => {
      'id': id,
      'kind': kind,
      'url': 'https://cdn.example.test/posts/7/$id.${kind == 'video' ? 'mp4' : 'jpg'}',
      'posterUrl': kind == 'video' ? 'https://cdn.example.test/posts/7/$id.jpg' : null,
      'width': 1200,
      'height': 900,
      'durationMs': kind == 'video' ? 8000 : null,
    };

Map<String, Object?> _post(int id, {List<Map<String, Object?>> media = const []}) => {
      'id': id,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'free',
      'title': '글 $id',
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-01T07:30:00Z',
      'media': media,
    };

({CommunityRepository repo, List<Uri> calls}) _repo(http.Response Function() respond) {
  final calls = <Uri>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      calls.add(request.url);
      return respond();
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: CommunityRepository(baseUrl: _base, client: client), calls: calls);
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUp(() {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.authenticated;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('게스트면 줄이 없고 서버도 안 부른다 — 홈의 다른 곁다리 카드와 같은 선', (tester) async {
    AuthState.status.value = AuthStatus.unauthenticated;
    final f = _repo(() => _json({'items': [_post(1, media: [_media(1)])], 'nextCursor': null, 'hasMore': false}));
    await tester.pumpWidget(_host(NeighborPhotoStrip(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('neighbor-photo-strip')), findsNothing);
    expect(f.calls, isEmpty);
  });

  testWidgets('사진 있는 글만 한 줄에 — 글만 있는 글은 없고, 영상은 재생 표시', (tester) async {
    final f = _repo(() => _json({
          'items': [
            _post(1, media: [_media(1)]),
            _post(2),
            _post(3, media: [_media(3, kind: 'video')]),
          ],
          'nextCursor': null,
          'hasMore': false,
        }));
    await tester.pumpWidget(_host(NeighborPhotoStrip(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('neighbor-photo-strip')), findsOneWidget);
    expect(find.text('이웃의 사진'), findsOneWidget);
    expect(find.byKey(const Key('photo-strip-1')), findsOneWidget);
    expect(find.byKey(const Key('photo-strip-3')), findsOneWidget);
    expect(find.byKey(const Key('photo-strip-2')), findsNothing, reason: '사진 없는 글은 줄에 없다');
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(f.calls.single.queryParameters['limit'], '20', reason: '목록 한 장만 받는다');
    expect(tester.takeException(), isNull);
  });

  testWidgets('열두 개까지만', (tester) async {
    final f = _repo(() => _json({
          'items': [for (var i = 1; i <= 20; i++) _post(i, media: [_media(i)])],
          'nextCursor': 'c',
          'hasMore': true,
        }));
    await tester.pumpWidget(_host(NeighborPhotoStrip(repository: f.repo)));
    await tester.pumpAndSettle();

    // 가로 목록은 보이는 것만 만든다 — 끝까지 끌어서 본다.
    await tester.drag(find.byType(ListView), const Offset(-3000, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-strip-12')), findsOneWidget);
    expect(find.byKey(const Key('photo-strip-13')), findsNothing, reason: '열셋째부터는 만들지 않는다');
  });

  testWidgets('사진 있는 글이 없으면 줄 자체가 없다', (tester) async {
    final f = _repo(() => _json({'items': [_post(1), _post(2)], 'nextCursor': null, 'hasMore': false}));
    await tester.pumpWidget(_host(NeighborPhotoStrip(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('neighbor-photo-strip')), findsNothing);
    expect(find.text('이웃의 사진'), findsNothing);
  });

  testWidgets('못 불러오면 줄 자체가 없다 — 홈이 고장 난 것처럼 보이면 안 된다', (tester) async {
    final f = _repo(() => _json({'error': 'down'}, status: 500));
    await tester.pumpWidget(_host(NeighborPhotoStrip(repository: f.repo)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('neighbor-photo-strip')), findsNothing);
    expect(find.textContaining('불러오지'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('타일은 그 글로, 더 보기는 벽으로', (tester) async {
    CommunityPost? opened;
    var more = 0;
    final f = _repo(() => _json({'items': [_post(5, media: [_media(5)])], 'nextCursor': null, 'hasMore': false}));
    await tester.pumpWidget(_host(NeighborPhotoStrip(
      repository: f.repo,
      onOpen: (p) => opened = p,
      onMore: () => more++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('photo-strip-5')));
    expect(opened?.id, 5);
    await tester.tap(find.byKey(const Key('photo-strip-more')));
    expect(more, 1);
  });
}

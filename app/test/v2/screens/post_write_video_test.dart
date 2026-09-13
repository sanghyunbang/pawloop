// 글쓰기 화면의 영상 첨부 — 세 단계로 올리고, 글에는 id 만 싣고, 올리는 중이면 저장을 잠근다 (#429).
//
// `post_write_media_test.dart` 와 같은 방식 — 진짜 `CommunityRepository`·`PostMediaRepository` 에
// `MockClient` 를 꽂는다(S3 로 가는 길은 따로). 영상 칸 자체의 규칙은 `post_media_field_video_test`.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/community_repository.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/data/media_picker.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/video_prep.dart';
import 'package:heat_trip_flutter/v2/screens/post_write_screen.dart';

import '../support/fake_media_picker.dart';
import '../support/mp4_fixture.dart';

const _base = 'https://api.example.test';
const _s3 = 'https://bucket.example.test/posts-video/7/clip.mp4?X-Amz-Signature=sig';

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

final _poster = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 0xFF, 0xD9]);

Map<String, Object?> _videoJson(int id) => {
      'id': id,
      'kind': 'video',
      'url': 'https://cdn.example.test/posts-video/7/$id.mp4',
      'posterUrl': 'https://cdn.example.test/posts/7/posters/$id.jpg',
      'width': 1280,
      'height': 720,
      'durationMs': 5000,
    };

Map<String, Object?> _post({List<int> mediaIds = const []}) => {
      'id': 9,
      'author': {'userId': 7, 'nickname': '보리아빠'},
      'board': 'pet_place',
      'loc': null,
      'contentId': null,
      'title': '제목',
      'body': '본문',
      'commentCount': 0,
      'reactions': {'help': 0, 'cute': 0, 'empathy': 0, 'mine': <String>[]},
      'createdAt': '2026-09-03T10:00:00Z',
      'media': [for (final id in mediaIds) _videoJson(id)],
    };

class _Server {
  final api = <http.Request>[];
  final s3 = <http.Request>[];
  final posts = <Map<String, Object?>>[];
  Completer<void>? s3Gate;

  Future<http.Response> apiCall(http.Request request) async {
    api.add(request);
    final path = request.url.path;
    if (request.method == 'POST' && path == '/media/videos') {
      return _json({'id': 601, 'key': 'posts-video/7/clip.mp4', 'uploadUrl': _s3}, status: 201);
    }
    if (request.method == 'POST' && path == '/media/601/complete') {
      return _json({'id': 601, 'url': 'https://cdn.example.test/posts-video/7/601.mp4', 'width': 1280, 'height': 720});
    }
    if (request.method == 'POST' && path == '/api/community/posts') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      posts.add(body);
      final ids = body['mediaIds'];
      return _json(_post(mediaIds: ids is List ? [for (final v in ids) (v as num).toInt()] : const []), status: 201);
    }
    return _json({'items': const [], 'nextCursor': null, 'hasMore': false});
  }

  Future<http.Response> s3Call(http.Request request) async {
    s3.add(request);
    if (s3Gate != null) await s3Gate!.future;
    return http.Response('', 200);
  }
}

typedef _Fixture = ({CommunityRepository repo, PostMediaRepository media, _Server server});

_Fixture _fixture() {
  final server = _Server();
  final client = AuthedClient(inner: MockClient(server.apiCall), baseUrl: _base, store: _FakeTokenStore());
  return (
    repo: CommunityRepository(baseUrl: _base, client: client),
    media: PostMediaRepository(baseUrl: _base, client: client, plainClient: MockClient(server.s3Call)),
    server: server,
  );
}

/// 준비 전체를 가짜로 — 픽스처 MP4 를 메모리에서 흘린다(가짜 시계 안에서 파일 IO 는 안 끝난다).
Future<PreparedVideo> _fakePrepare(String path) async {
  final bytes = mp4Fixture(withLocation: false);
  return PreparedVideo(
    path: '/cache/prepared.mp4',
    size: bytes.length,
    width: 1280,
    height: 720,
    durationMs: 5000,
    poster: _poster,
    source: () => Stream.value(bytes),
  );
}

Widget _screen(_Fixture f) => PostWriteScreen(
      repository: f.repo,
      media: f.media,
      picker: FakeMediaPicker((_) => const [], supplyVideo: () => const PickedVideo(name: 'walk.mov', path: '/g/walk.mov')),
      prepare: (bytes) async => ImagePrep.prepareSync(bytes),
      prepareVideo: _fakePrepare,
    );

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return TextButton(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen)),
        child: const Text('열기'),
      );
    }),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '제목');
  await tester.enterText(find.byType(TextField).last, '본문');
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  setUp(() {
    LocationUploadPolicy.setForTest(true);
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single;
    view.physicalSize = const Size(800, 1400);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    LocationUploadPolicy.resetForTest();
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.single.reset();
  });

  testWidgets('영상을 고르면 세 단계로 올라가고, 글에는 파일이 아니라 mediaIds 만 실린다', (tester) async {
    final f = _fixture();
    await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.byKey(const Key('post-media-add-video')));
    await tester.pumpAndSettle();
    expect(f.server.s3, hasLength(1), reason: '고르는 순간 올린다 — S3 로 직접');

    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();

    final body = f.server.posts.single;
    expect(body['mediaIds'], [601]);
    expect(body.keys, isNot(contains('files')));
    expect([for (final r in f.server.api) r.url.path],
        ['/media/videos', '/media/601/complete', '/api/community/posts']);
  });

  testWidgets('S3 로 올리는 중에는 저장이 잠긴다 — 영상 없는 글이 조용히 올라가지 않는다', (tester) async {
    final f = _fixture();
    f.server.s3Gate = Completer<void>();
    await _open(tester, _screen(f));

    await _fill(tester);
    await _tapVisible(tester, find.byKey(const Key('post-media-add-video')));
    for (var i = 0; i < 10 && f.server.s3.isEmpty; i++) {
      await tester.pump();
    }

    await _tapVisible(tester, find.text('올리기'));
    await tester.pump();
    expect(find.text('사진·영상을 올리는 중이에요 · 잠시만요'), findsOneWidget);
    expect(f.server.posts, isEmpty);

    f.server.s3Gate!.complete();
    f.server.s3Gate = null;
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('올리기'));
    await tester.pumpAndSettle();
    expect(f.server.posts.single['mediaIds'], [601]);
  });
}

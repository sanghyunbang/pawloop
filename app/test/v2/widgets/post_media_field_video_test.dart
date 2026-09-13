// 글쓰기의 영상 칸 — 고른 영상이 준비(720p · 위치 상자 덮기 · 포스터)를 지나 **세 단계로** 올라가고,
// 한 글에 하나다 (#429, 서버 #435).
//
// 준비 자체(덮기·확인)는 `video_prep_test` 가 바이트로 잰다. 여기는 그 뒤 — 위젯 → 저장소 →
// `POST /media/videos` → S3 PUT(토큰 없이) → `complete` → `mediaIds` 까지의 배선이다. 가짜 시계
// 안에서 파일 IO 는 안 끝나므로 준비 결과는 메모리에서 흘린다(`PreparedVideo.source`).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/media_picker.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/video_prep.dart';
import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_field.dart';

import '../support/fake_media_picker.dart';
import '../support/gps_jpeg.dart';
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

final _poster = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 5, 5, 5, 0xFF, 0xD9]);

class _Server {
  final api = <http.Request>[];
  final s3 = <http.Request>[];
  final deleted = <String>[];

  /// S3 PUT 의 응답 전에 기다릴 문. 올리는 중인 상태를 잡는 데 쓴다.
  Completer<void>? s3Gate;

  int _nextPhotoId = 501;

  Future<http.Response> apiCall(http.Request request) async {
    api.add(request);
    final path = request.url.path;
    if (request.method == 'POST' && path == '/media/videos') {
      return _json({'id': 601, 'key': 'posts-video/7/clip.mp4', 'uploadUrl': _s3}, status: 201);
    }
    if (request.method == 'POST' && path == '/media/601/complete') {
      return _json({
        'id': 601,
        'url': 'https://cdn.example.test/posts-video/7/clip.mp4',
        'posterUrl': 'https://cdn.example.test/posts/7/posters/p.jpg',
        'width': 1280,
        'height': 720,
        'durationMs': 5000,
      });
    }
    if (request.method == 'POST' && path == '/media') {
      final id = _nextPhotoId++;
      return _json([
        {'id': id, 'url': 'https://cdn.example.test/posts/7/$id.jpg', 'width': 24, 'height': 40}
      ]);
    }
    if (request.method == 'DELETE' && path.startsWith('/media/')) {
      deleted.add(request.url.pathSegments.last);
      return http.Response('', 204);
    }
    return _json({}, status: 404);
  }

  Future<http.Response> s3Call(http.Request request) async {
    s3.add(request);
    if (s3Gate != null) await s3Gate!.future;
    return http.Response('', 200);
  }
}

({PostMediaRepository repo, _Server server}) _fixture() {
  final server = _Server();
  final client = AuthedClient(inner: MockClient(server.apiCall), baseUrl: _base, store: _FakeTokenStore());
  return (
    repo: PostMediaRepository(baseUrl: _base, client: client, plainClient: MockClient(server.s3Call)),
    server: server,
  );
}

const _video = PickedVideo(name: 'walk.mov', path: '/gallery/walk.mov');

/// 준비 전체를 가짜로 — 720p 파일 대신 픽스처 MP4 를 메모리에서 흘린다. 덮기·확인은 `video_prep_test` 의 일이다.
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

Future<PreparedImage> _prepareInline(Uint8List bytes) async => ImagePrep.prepareSync(bytes);

Widget _host(PostMediaField field) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: field)),
    );

void main() {
  testWidgets('영상을 고르면 준비를 지나 세 단계로 올라가고, 칸에 재생 표시와 길이가 선다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker((_) => const [], supplyVideo: () => _video);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add-video')));
    await tester.pumpAndSettle();

    expect([for (final r in f.server.api) r.url.path], ['/media/videos', '/media/601/complete'],
        reason: '자리 잡기 → (S3) → 끝내기');
    expect(f.server.s3, hasLength(1));
    expect(f.server.s3.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    expect(f.server.s3.single.bodyBytes, mp4Fixture(withLocation: false), reason: '준비된 파일이 그대로 나간다');
    expect(selections.last.ids, [601]);
    expect(selections.last.busy, isFalse);
    expect(selections.last.hasFailure, isFalse);

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.byKey(const Key('post-media-duration-0')), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
    expect(find.text('1 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);
    expect(find.byKey(const Key('post-media-add-video')), findsNothing, reason: '한 글에 영상은 하나');
    expect(find.byKey(const Key('post-media-add')), findsOneWidget, reason: '사진은 더 넣을 수 있다');
  });

  testWidgets('떼면 id 가 빠지고 서버에서도 지우며, 영상 추가가 돌아온다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker((_) => const [], supplyVideo: () => _video);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add-video')));
    await tester.pumpAndSettle();
    expect(selections.last.ids, [601]);

    await tester.tap(find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();

    expect(selections.last.ids, isEmpty);
    expect(f.server.deleted, ['601']);
    expect(find.byKey(const Key('post-media-add-video')), findsOneWidget);
  });

  testWidgets('준비가 거절하면(60초) 그 칸이 실패고 이유가 보이며, 서버에는 가지 않는다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker((_) => const [], supplyVideo: () => _video);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: (_) async => throw const VideoPrepException('영상은 60초까지 올릴 수 있어요'),
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add-video')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-error-0')), findsOneWidget);
    expect(find.text('영상은 60초까지 올릴 수 있어요'), findsOneWidget, reason: '다시 눌러도 같으니 이유만 쓴다');
    expect(selections.last.hasFailure, isTrue);
    expect(selections.last.ids, isEmpty);
    expect(f.server.api, isEmpty);
    expect(f.server.s3, isEmpty);
  });

  testWidgets('S3 로 올리는 동안은 busy 고 칸에 진행률이 있다', (tester) async {
    final f = _fixture();
    f.server.s3Gate = Completer<void>();
    final picker = FakeMediaPicker((_) => const [], supplyVideo: () => _video);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add-video')));
    // 준비와 자리 잡기를 지나 S3 앞에서 멈출 때까지 — 마이크로태스크 몇 바퀴.
    for (var i = 0; i < 10 && f.server.s3.isEmpty; i++) {
      await tester.pump();
    }

    expect(selections.last.busy, isTrue);
    expect(find.byKey(const Key('post-media-working-0')), findsOneWidget);
    expect(find.byKey(const Key('post-media-progress-0')), findsOneWidget);
    expect(f.server.api.map((r) => r.url.path), ['/media/videos'], reason: '아직 끝내기 전이다');

    f.server.s3Gate!.complete();
    f.server.s3Gate = null;
    await tester.pumpAndSettle();

    expect(selections.last.ids, [601]);
    expect(selections.last.busy, isFalse);
    expect(find.byKey(const Key('post-media-working-0')), findsNothing);
  });

  testWidgets('고치기 — 붙어 있던 영상은 올리지 않고 재생 표시와 길이로 그리며, 영상 추가는 없다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker((_) => const [], supplyVideo: () => _video);
    const existing = PostMedia(
      id: 77,
      kind: PostMediaKind.video,
      url: 'https://cdn.example.test/posts-video/7/77.mp4',
      posterUrl: 'https://cdn.example.test/posts/7/posters/77.jpg',
      width: 1280,
      height: 720,
      durationMs: 8000,
    );

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      initial: const [existing],
      onChanged: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(f.server.api, isEmpty);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.text('0:08'), findsOneWidget);
    expect(find.byKey(const Key('post-media-add-video')), findsNothing);
    expect(find.byKey(const Key('post-media-add')), findsOneWidget);
  });

  testWidgets('고르기를 닫으면 아무 일도 없다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker((_) => const []);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add-video')));
    await tester.pumpAndSettle();

    expect(picker.videoCalls, 1);
    expect(f.server.api, isEmpty);
    expect(selections.last.busy, isFalse);
    expect(selections.last.ids, isEmpty);
    expect(find.byKey(const Key('post-media-add-video')), findsOneWidget);
  });

  testWidgets('열 개가 차면 영상 추가도 사라진다 — 상한은 사진·영상을 합쳐 센다', (tester) async {
    final f = _fixture();
    final picker = FakeMediaPicker(
      (limit) => [for (var i = 0; i < limit; i++) PickedImage(name: '$i.jpg', bytes: gpsJpeg())],
      supplyVideo: () => _video,
    );

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      prepareVideo: _fakePrepare,
      onChanged: (_) {},
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-add-video')), findsNothing);
    expect(find.byKey(const Key('post-media-add')), findsNothing);
  });
}

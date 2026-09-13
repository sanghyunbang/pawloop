// 글쓰기의 사진 칸 — 고른 사진이 **다시 인코딩을 지나서만** 나가고, 순서·떼기·재시도·상한이
// 맞는지 (#429).
//
// 첫 테스트가 이 PR 의 요점이다: GPS 를 실은 사진을 고르게 하고, `MockClient` 가 받은 바이트를
// 다시 디코드해 GPS IFD 가 비었는지 잰다. 위젯 → 다시 인코딩 → 저장소 → 전송까지 진짜
// 배선이다. `ImagePrep.prepareSync` 의 `exif = ExifData()` 한 줄을 빼면 여기가 빨간불이다.
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
import 'package:heat_trip_flutter/v2/domain/post_media.dart';
import 'package:heat_trip_flutter/v2/widgets/post_media_field.dart';

import '../support/fake_media_picker.dart';
import '../support/gps_jpeg.dart';
import '../support/multipart.dart';

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

class _Server {
  final uploads = <http.Request>[];
  final deleted = <String>[];

  /// 응답 전에 기다릴 문. 비어 있으면 바로 답한다.
  Completer<void>? gate;

  /// 처음 n 번의 업로드를 500 으로 떨어뜨린다.
  int failFirst = 0;

  int _nextId = 501;

  Future<http.Response> call(http.Request request) async {
    if (request.method == 'POST' && request.url.path == '/media') {
      uploads.add(request);
      if (gate != null) await gate!.future;
      if (failFirst > 0) {
        failFirst--;
        return _json({'error': {'code': 'INTERNAL', 'message': '서버 오류'}}, status: 500);
      }
      final parts = parseMultipart(request);
      final id = _nextId++;
      return _json([
        {
          'id': id,
          'url': 'https://cdn.example.test/posts/7/$id.jpg',
          'width': int.tryParse(partNamed(parts, 'width').text),
          'height': int.tryParse(partNamed(parts, 'height').text),
        }
      ]);
    }
    if (request.method == 'DELETE' && request.url.path.startsWith('/media/')) {
      deleted.add(request.url.pathSegments.last);
      return http.Response('', 204);
    }
    return _json({}, status: 404);
  }
}

({PostMediaRepository repo, _Server server}) fixture() {
  final server = _Server();
  final client = AuthedClient(
    inner: MockClient(server.call),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: PostMediaRepository(baseUrl: _base, client: client), server: server);
}

PickedImage _gpsPhoto([String name = 'IMG_0001.HEIC']) =>
    PickedImage(name: name, bytes: gpsJpeg());

/// 격리 스레드를 안 탄다 — 테스트는 바로 돈다. 하는 일은 같은 `prepareSync` 다.
Future<PreparedImage> _prepareInline(Uint8List bytes) async => ImagePrep.prepareSync(bytes);

Widget _host(PostMediaField field) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: field)),
    );

void main() {
  testWidgets('고른 사진은 다시 인코딩을 지나서만 나간다 — 나간 바이트에 GPS 가 없다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker((_) => [_gpsPhoto()]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    final request = f.server.uploads.single;
    final parts = parseMultipart(request);
    final sent = partNamed(parts, 'files');
    final exif = exifOf(sent.body);
    expect(exif.gpsIfd.isEmpty, isTrue, reason: '촬영 좌표가 단말을 떠나면 안 된다 (#235 A안)');
    expect(exif.isEmpty, isTrue, reason: 'EXIF 가 통째로 없다');
    expect(sent.body, isNot(equals(gpsJpeg())), reason: '원본 그대로가 아니다');
    expect(sent.filename, 'IMG_0001.jpg', reason: 'HEIC 를 골라도 나가는 것은 JPEG 다');
    expect(sent.contentType, 'image/jpeg');

    // 회전(orientation 6)을 구운 크기를 서버에 알린다 — 가로 40×24 가 세로 24×40 이다.
    expect(partNamed(parts, 'width').text, '24');
    expect(partNamed(parts, 'height').text, '40');

    expect(selections.last.ids, [501]);
    expect(selections.last.busy, isFalse);
    expect(find.text('1 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);
  });

  testWidgets('올리는 동안은 busy 고 칸에 진행 표시가 있다 — 끝나면 고른 순서대로 id 가 선다', (tester) async {
    final f = fixture();
    f.server.gate = Completer<void>();
    final picker = FakeMediaPicker((_) => [_gpsPhoto('a.jpg'), _gpsPhoto('b.jpg')]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pump();
    await tester.pump();

    expect(selections.last.busy, isTrue);
    expect(find.byKey(const Key('post-media-working-0')), findsOneWidget);
    expect(f.server.uploads.length, 1, reason: '한 장씩 순서대로 — 둘째는 첫째가 끝난 뒤 나간다');

    f.server.gate!.complete();
    f.server.gate = null;
    await tester.pumpAndSettle();

    expect(f.server.uploads.length, 2);
    expect(selections.last.ids, [501, 502], reason: '고른 순서가 곧 카드의 순서다');
    expect(selections.last.busy, isFalse);
    expect(find.byKey(const Key('post-media-working-0')), findsNothing);
    expect(find.byKey(const Key('post-media-working-1')), findsNothing);
  });

  testWidgets('떼면 id 가 빠지고 올려 둔 것은 서버에서도 지운다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker((_) => [_gpsPhoto()]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();
    expect(selections.last.ids, [501]);

    await tester.tap(find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();

    expect(selections.last.ids, isEmpty);
    expect(f.server.deleted, ['501']);
    expect(find.text('0 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);
  });

  testWidgets('실패한 칸은 hasFailure 로 알리고, 누르면 다시 올린다', (tester) async {
    final f = fixture();
    f.server.failFirst = 1;
    final picker = FakeMediaPicker((_) => [_gpsPhoto()]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-error-0')), findsOneWidget);
    expect(find.text('올리지 못했어요\n눌러서 다시'), findsOneWidget);
    expect(selections.last.hasFailure, isTrue);
    expect(selections.last.ids, isEmpty);

    await tester.tap(find.byKey(const Key('post-media-slot-0')));
    await tester.pumpAndSettle();

    expect(f.server.uploads.length, 2);
    expect(find.byKey(const Key('post-media-error-0')), findsNothing);
    expect(selections.last.hasFailure, isFalse);
    expect(selections.last.ids, [501]);
  });

  testWidgets('읽을 수 없는 파일은 올리지 않고 그 칸만 실패다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker(
        (_) => [PickedImage(name: 'broken.bin', bytes: Uint8List.fromList([1, 2, 3]))]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    expect(f.server.uploads, isEmpty);
    expect(find.byKey(const Key('post-media-error-0')), findsOneWidget);
    expect(selections.last.hasFailure, isTrue);
  });

  testWidgets('열 장이 차면 추가 칸이 사라진다 — 상한은 저장소 상수고 고르기에도 남은 자리를 준다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker((limit) => [for (var i = 0; i < limit; i++) _gpsPhoto('$i.jpg')]);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, PostMediaRepository.maxPerPost);
    expect(selections.last.ids.length, 10);
    expect(find.byKey(const Key('post-media-add')), findsNothing);
    expect(find.text('10 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('post-media-remove-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-media-add')), findsOneWidget, reason: '자리가 나면 다시 고를 수 있다');
    expect(selections.last.ids.length, 9);
  });

  testWidgets('고치기 — 이미 붙은 사진은 올리지 않고, 떼도 DELETE /media 를 부르지 않는다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker((_) => const []);
    final selections = <PostMediaSelection>[];
    const existing = PostMedia(
      id: 77,
      kind: PostMediaKind.image,
      url: 'https://cdn.example.test/posts/7/77.jpg',
      width: 1600,
      height: 1200,
    );

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      initial: const [existing],
      onChanged: selections.add,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-media-slot-0')), findsOneWidget);
    expect(f.server.uploads, isEmpty, reason: '서버에 있는 것을 다시 올리지 않는다');
    expect(find.text('1 / 10장 · 위치 정보는 지우고 올려요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('post-media-remove-0')));
    await tester.pumpAndSettle();

    expect(selections.last.ids, isEmpty);
    expect(f.server.deleted, isEmpty,
        reason: '글에 붙은 것은 글 고치기의 mediaIds 가 다룬다 — 여기서 지우면 저장 전에 사라진다');
  });

  testWidgets('고르기를 닫으면 아무 일도 없다', (tester) async {
    final f = fixture();
    final picker = FakeMediaPicker((_) => const []);
    final selections = <PostMediaSelection>[];

    await tester.pumpWidget(_host(PostMediaField(
      repository: f.repo,
      picker: picker,
      prepare: _prepareInline,
      onChanged: selections.add,
    )));
    await tester.tap(find.byKey(const Key('post-media-add')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(f.server.uploads, isEmpty);
    expect(selections.last.busy, isFalse);
    expect(selections.last.ids, isEmpty);
  });
}

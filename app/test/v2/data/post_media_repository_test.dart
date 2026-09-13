// 사진 업로드 저장소 — 계약의 multipart 필드와 응답 키로 왕복한다 (#429, 서버 #430).
//
// 진짜 `AuthedClient` 에 `MockClient` 를 꽂는다 — 토큰 헤더가 붙는지, multipart 가 어떤
// 모양으로 나가는지까지 한 번에 지난다.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';

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

/// 계약의 `MediaItem` — 서버가 `POST /media` 에 돌려주는 모양 그대로.
Map<String, Object?> _mediaItem({int id = 501, int? width = 24, int? height = 40}) => {
      'id': id,
      'key': 'posts/7/$id.jpg',
      'url': 'https://cdn.example.test/posts/7/$id.jpg',
      'contentType': 'image/jpeg',
      'size': 1234,
      'category': 'POST_IMAGE',
      'refType': null,
      'refId': null,
      'status': 'READY',
      'posterUrl': null,
      'width': width,
      'height': height,
      'durationMs': null,
    };

({PostMediaRepository repo, List<http.Request> calls}) fixture(
  FutureOr<http.Response> Function(http.Request request) handler,
) {
  final calls = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      calls.add(request);
      return handler(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: PostMediaRepository(baseUrl: _base, client: client), calls: calls);
}

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);

void main() {
  test('POST /media 에 multipart 로 — files · category=POST_IMAGE · width · height, 토큰 헤더', () async {
    final f = fixture((_) => _json([_mediaItem()]));

    final uploaded = await f.repo.upload(jpegBytes: _jpeg, width: 24, height: 40, filename: 'IMG_1.jpg');

    final request = f.calls.single;
    expect((request.method, request.url.path), ('POST', '/media'));
    expect(request.headers['authorization'], 'Bearer AT-1', reason: '업로드는 로그인한 사람만');
    expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));

    final parts = parseMultipart(request);
    expect(partNamed(parts, 'category').text, PostMediaRepository.category);
    expect(partNamed(parts, 'width').text, '24');
    expect(partNamed(parts, 'height').text, '40');
    final file = partNamed(parts, 'files');
    expect(file.filename, 'IMG_1.jpg');
    expect(file.contentType, 'image/jpeg', reason: '서버 ImageValidator 가 파트의 content-type 을 본다');
    expect(file.body, _jpeg, reason: '받은 바이트가 그대로 나간다 — 여기서 다시 인코딩하지 않는다');
    expect(parts.length, 4, reason: '계약에 없는 필드를 더 싣지 않는다');

    expect(uploaded.id, 501);
    expect(uploaded.url, 'https://cdn.example.test/posts/7/501.jpg');
    expect((uploaded.width, uploaded.height), (24, 40));
  });

  test('서버 상한(10MB)을 넘는 바이트는 보내지도 않는다', () async {
    final f = fixture((_) => _json([_mediaItem()]));
    final huge = Uint8List(PostMediaRepository.maxBytes + 1);

    await expectLater(
      f.repo.upload(jpegBytes: huge, width: 1, height: 1),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)),
    );
    expect(f.calls, isEmpty);
  });

  test('400 은 rejected 이고 서버의 문구를 그대로 든다', () async {
    final f = fixture((_) => _json(
          {'error': {'code': 'UNSUPPORTED_MEDIA_TYPE', 'message': '지원하지 않는 형식이에요'}},
          status: 400,
        ));

    await expectLater(
      f.repo.upload(jpegBytes: _jpeg, width: 1, height: 1),
      throwsA(isA<PostMediaFailure>()
          .having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)
          .having((e) => e.label, 'label', '지원하지 않는 형식이에요')),
    );
  });

  test('429 는 rateLimited — 업로드 버킷이 분당 20 이다', () async {
    final f = fixture((_) => _json({}, status: 429));
    await expectLater(
      f.repo.upload(jpegBytes: _jpeg, width: 1, height: 1),
      throwsA(isA<PostMediaFailure>()
          .having((e) => e.kind, 'kind', PostMediaFailureKind.rateLimited)
          .having((e) => e.label, 'label', '잠시 후 다시 시도해 주세요')),
    );
  });

  test('연결이 끊기면 network', () async {
    final f = fixture((_) => throw http.ClientException('연결 실패'));
    await expectLater(
      f.repo.upload(jpegBytes: _jpeg, width: 1, height: 1),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.network)),
    );
  });

  test('200 인데 모양이 아니면 network — id 없는 성공은 성공이 아니다', () async {
    final f = fixture((_) => _json([]));
    await expectLater(
      f.repo.upload(jpegBytes: _jpeg, width: 1, height: 1),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.network)),
    );
  });

  test('DELETE /media/{id} — 204 면 끝, 404 면 notFound', () async {
    final f = fixture((request) => http.Response('', request.url.path == '/media/501' ? 204 : 404));

    await f.repo.delete(501);
    expect((f.calls.single.method, f.calls.single.url.path), ('DELETE', '/media/501'));

    await expectLater(
      f.repo.delete(502),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.notFound)),
    );
  });

  test('MediaItem 파서 — id·url 이 없으면 null', () {
    expect(UploadedPostMedia.tryParse(_mediaItem()), isNotNull);
    expect(UploadedPostMedia.tryParse({..._mediaItem(), 'id': null}), isNull);
    expect(UploadedPostMedia.tryParse({..._mediaItem(), 'url': ''}), isNull);
    expect(UploadedPostMedia.tryParse(_mediaItem(width: null, height: null))!.width, isNull);
  });

  test('상한 상수가 서버와 같다 — 한 글 10장, 한 장 10MB', () {
    expect(PostMediaRepository.maxPerPost, 10);
    expect(PostMediaRepository.maxBytes, 10 * 1024 * 1024);
  });
}

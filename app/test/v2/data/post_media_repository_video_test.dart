// 영상 세 단계 — 자리 잡기(JSON) · S3 PUT(토큰 없이) · complete(포스터) 가 계약의 키로 나간다
// (#429, 서버 #435).
//
// 진짜 `AuthedClient` 에 `MockClient` 를 꽂고, S3 로 가는 길에는 **다른** `MockClient` 를 꽂는다 —
// 두 길이 갈라져 있어야 토큰이 S3 로 새지 않는 것을 잴 수 있다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/data/video_prep.dart';

import '../support/multipart.dart';

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

/// 계약의 `VideoUploadTicket`.
Map<String, Object?> _ticket({int id = 601}) => {'id': id, 'key': 'posts-video/7/clip.mp4', 'uploadUrl': _s3};

/// 계약의 `MediaItem` — `complete` 가 돌려주는 모양.
Map<String, Object?> _readyItem({int id = 601}) => {
      'id': id,
      'key': 'posts-video/7/clip.mp4',
      'url': 'https://cdn.example.test/posts-video/7/clip.mp4',
      'contentType': 'video/mp4',
      'size': 3000,
      'category': 'POST_VIDEO',
      'refType': null,
      'refId': null,
      'status': 'ready',
      'posterUrl': 'https://cdn.example.test/posts/7/posters/p.jpg',
      'width': 1280,
      'height': 720,
      'durationMs': 5000,
    };

final _poster = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7, 7, 7, 0xFF, 0xD9]);

/// API 와 S3 를 한 곳에서 받는 가짜 서버 — 두 길은 따로 센다.
class _Server {
  final api = <http.Request>[];
  final s3 = <http.Request>[];
  int ticketStatus = 201;
  Object? ticketBody;
  int putStatus = 200;
  int completeStatus = 200;
  Object? completeBody;

  Future<http.Response> apiCall(http.Request request) async {
    api.add(request);
    if (request.method == 'POST' && request.url.path == '/media/videos') {
      return _json(ticketBody ?? _ticket(), status: ticketStatus);
    }
    if (request.method == 'POST' && request.url.path == '/media/601/complete') {
      return _json(completeBody ?? _readyItem(), status: completeStatus);
    }
    return _json({}, status: 404);
  }

  Future<http.Response> s3Call(http.Request request) async {
    s3.add(request);
    return http.Response('', putStatus);
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

Uint8List _clipBytes() => Uint8List.fromList(List<int>.generate(3000, (i) => (i * 13) % 251));

Future<PreparedVideo> _video(Directory dir, {int? width = 1280, int? height = 720, int? size}) async {
  final path = '${dir.path}/clip.mp4';
  final bytes = _clipBytes();
  await File(path).writeAsBytes(bytes);
  return PreparedVideo(
    path: path,
    size: size ?? bytes.length,
    width: width,
    height: height,
    durationMs: 5000,
    poster: _poster,
  );
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('video-repo-'));
  tearDown(() => dir.delete(recursive: true));

  test('세 단계가 순서대로 — 자리 잡기(JSON·토큰) → S3 PUT(토큰 없이·Content-Type) → complete(poster)', () async {
    final f = _fixture();
    final progress = <double>[];

    final uploaded = await f.repo.uploadVideo(await _video(dir), onProgress: progress.add);

    // ① 계약 VideoUploadRequest 의 키 그대로, 더도 덜도 아니다.
    final reserve = f.server.api.first;
    expect((reserve.method, reserve.url.path), ('POST', '/media/videos'));
    expect(reserve.headers['authorization'], 'Bearer AT-1');
    expect(reserve.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(reserve.body), {
      'contentType': 'video/mp4',
      'size': 3000,
      'width': 1280,
      'height': 720,
      'durationMs': 5000,
    });

    // ② 서명 URL 그대로, 토큰 없이, 서명에 묶인 Content-Type 으로, 파일 바이트 그대로.
    final put = f.server.s3.single;
    expect(put.method, 'PUT');
    expect(put.url.toString(), _s3);
    expect(put.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')),
        reason: '서명 URL 에 Authorization 이 얹히면 S3 가 거절한다');
    expect(put.headers['content-type'], 'video/mp4');
    expect(put.bodyBytes, _clipBytes());

    // ③ 포스터 한 장. 계약에 없는 필드는 없다.
    final complete = f.server.api[1];
    expect((complete.method, complete.url.path), ('POST', '/media/601/complete'));
    expect(complete.headers['authorization'], 'Bearer AT-1');
    final parts = parseMultipart(complete);
    expect(parts, hasLength(1));
    final poster = partNamed(parts, 'poster');
    expect(poster.contentType, 'image/jpeg');
    expect(poster.body, _poster);

    expect(f.server.api, hasLength(2), reason: 'API 는 두 번 — 자리 잡기와 끝내기');
    expect(uploaded.id, 601);
    expect(uploaded.url, 'https://cdn.example.test/posts-video/7/clip.mp4');

    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]), reason: '진행률은 되돌아가지 않는다');
    }
  });

  test('크기를 모르면 width·height 키를 안 싣는다 — 둘은 함께여야 해서', () async {
    final f = _fixture();
    await f.repo.uploadVideo(await _video(dir, width: null, height: null));
    final body = jsonDecode(f.server.api.first.body) as Map;
    expect(body.keys, isNot(contains('width')));
    expect(body.keys, isNot(contains('height')));
  });

  test('자리 잡기가 400 이면 rejected 에 서버 문구 — S3 에는 가지도 않는다', () async {
    final f = _fixture();
    f.server.ticketStatus = 400;
    f.server.ticketBody = {'error': {'code': 'VALIDATION', 'message': '영상은 60초까지예요.'}};

    await expectLater(
      f.repo.uploadVideo(await _video(dir)),
      throwsA(isA<PostMediaFailure>()
          .having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)
          .having((e) => e.label, 'label', '영상은 60초까지예요.')),
    );
    expect(f.server.s3, isEmpty);
    expect(f.server.api, hasLength(1));
  });

  test('S3 가 403 이면 서명이 만료된 것 — 다시 시도하라고 하고 complete 는 안 부른다', () async {
    final f = _fixture();
    f.server.putStatus = 403;

    await expectLater(
      f.repo.uploadVideo(await _video(dir)),
      throwsA(isA<PostMediaFailure>()
          .having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)
          .having((e) => e.label, 'label', contains('너무 오래'))),
    );
    expect(f.server.api, hasLength(1), reason: 'S3 에 안 올라갔는데 끝냈다고 하지 않는다');
  });

  test('S3 가 500 이면 network', () async {
    final f = _fixture();
    f.server.putStatus = 500;
    await expectLater(
      f.repo.uploadVideo(await _video(dir)),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.network)),
    );
    expect(f.server.api, hasLength(1));
  });

  test('complete 가 409 면 아직 S3 에 없는 것 — rejected 에 서버 문구', () async {
    final f = _fixture();
    f.server.completeStatus = 409;
    f.server.completeBody = {'error': {'code': 'CONFLICT', 'message': '영상이 아직 올라오지 않았습니다.'}};

    await expectLater(
      f.repo.uploadVideo(await _video(dir)),
      throwsA(isA<PostMediaFailure>()
          .having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)
          .having((e) => e.label, 'label', '영상이 아직 올라오지 않았습니다.')),
    );
  });

  test('150MB 를 넘는 파일은 보내지도 않는다', () async {
    final f = _fixture();
    final huge = await _video(dir, size: VideoLimits.maxBytes + 1);

    await expectLater(
      f.repo.uploadVideo(huge),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.rejected)),
    );
    expect(f.server.api, isEmpty);
    expect(f.server.s3, isEmpty);
  });

  test('티켓이 모양이 아니면 network — uploadUrl 이 URL 이 아니거나 id 가 없으면', () async {
    expect(VideoUploadTicket.tryParse(_ticket()), isNotNull);
    expect(VideoUploadTicket.tryParse({..._ticket(), 'id': null}), isNull);
    expect(VideoUploadTicket.tryParse({..._ticket(), 'uploadUrl': 'not a url'}), isNull);
    expect(VideoUploadTicket.tryParse({..._ticket(), 'key': 3}), isNull);

    final f = _fixture();
    f.server.ticketBody = {'id': 601, 'key': 'k'};
    await expectLater(
      f.repo.uploadVideo(await _video(dir)),
      throwsA(isA<PostMediaFailure>().having((e) => e.kind, 'kind', PostMediaFailureKind.network)),
    );
    expect(f.server.s3, isEmpty);
  });
}

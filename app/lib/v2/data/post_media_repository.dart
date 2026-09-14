// 글에 붙일 사진의 서버 왕복 — 이슈 #429, 서버는 PR #430.
//
// ## 한 요청에 한 장
//
// 서버는 여러 장을 받지만 `width`·`height` 는 파일이 하나일 때만 받는다. 그리고 한 장씩
// 올려야 순서가 올린 순서다 — 서버가 `id` 순으로 돌려주고, 그 `id` 는 올린 순이다.
// 화면도 한 장씩 올려야 칸마다 "올리는 중" 을 따로 그릴 수 있다.
//
// ## 레거시 `lib/shared/media/` 를 안 쓴다
//
// 그 모듈은 Provider 로 주입받는 완성품인데 부르는 화면이 없다(#94 · #429). v2 화면은 생성자로
// 저장소를 받는다 — 테스트가 `MockClient` 를 꽂는 자리다. 같은 multipart 조립을 여기 짧게
// 다시 적는 편이 그 모듈에 기대는 것보다 싸다. 지울지는 여기서 정하지 않는다.
//
// ## 실패는 종류로 말한다
//
// `CommunityFailure` 와 같은 모양이다. 400 은 서버가 이유를 준다(너무 크다 · 형식이 아니다) —
// 그 문구를 그대로 쓴다. 지어내지 않는다.
//
// ## 영상은 세 단계다 (서버 #435)
//
// 영상은 서버를 안 지난다 — `api.heattrip.link` 앞의 Cloudflare 가 본문을 100MB 에서 끊는다.
// ① `POST /media/videos` 로 자리를 잡고(서명 PUT, 15분) ② 그 URL 로 S3 에 **직접** 올리고
// ③ `POST /media/{id}/complete` 에 포스터를 실어 끝낸다. ② 는 `AuthedClient` 를 **안 탄다** —
// 서명 URL 에 `Authorization` 을 얹으면 S3 가 "인증이 둘" 이라고 거절한다. 그래서 토큰 없는
// 클라이언트가 따로 있다([PostMediaRepository.new] 의 `plainClient`).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import 'video_prep.dart';

/// 올라간 사진 하나 — 계약의 `MediaItem` 중 앱이 쓰는 것.
class UploadedPostMedia {
  /// `PostInput.mediaIds` 에 싣는 값.
  final int id;
  final String url;
  final int? width;
  final int? height;

  const UploadedPostMedia({required this.id, required this.url, this.width, this.height});

  /// 계약의 키(`id`·`url`·`width`·`height`)에서. 모양이 아니면 `null`.
  static UploadedPostMedia? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final url = json['url'];
    if (id is! num || url is! String || url.isEmpty) return null;
    return UploadedPostMedia(
      id: id.toInt(),
      url: url,
      width: json['width'] is num ? (json['width'] as num).toInt() : null,
      height: json['height'] is num ? (json['height'] as num).toInt() : null,
    );
  }
}

/// 영상 세 단계의 첫 답 — 계약의 `VideoUploadTicket`.
class VideoUploadTicket {
  /// `complete` 에 쓰고, 그다음 `PostInput.mediaIds` 에 싣는 값.
  final int id;
  final String key;

  /// 서명 PUT URL. 15분 뒤에는 S3 가 403 을 준다.
  final Uri uploadUrl;

  const VideoUploadTicket({required this.id, required this.key, required this.uploadUrl});

  /// 계약의 키(`id`·`key`·`uploadUrl`)에서. 모양이 아니면 `null`.
  static VideoUploadTicket? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final key = json['key'];
    final url = json['uploadUrl'];
    if (id is! num || key is! String || url is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return VideoUploadTicket(id: id.toInt(), key: key, uploadUrl: uri);
  }
}

enum PostMediaFailureKind {
  /// 연결이 없다. 다시 보내면 된다.
  network,

  /// 로그인이 필요하다.
  unauthorized,

  /// 잠시 그만 보내라(429). 업로드 버킷이 분당 20 이다.
  rateLimited,

  /// 서버가 거절했다(400) — 너무 크거나 형식이 아니다. [PostMediaFailure.message] 가 이유다.
  rejected,

  /// 지우려는 것이 없거나 내 것이 아니다(404). 서버는 둘을 구분해 주지 않는다.
  notFound,
}

class PostMediaFailure implements Exception {
  final PostMediaFailureKind kind;

  /// 서버가 준 문구. 없으면 종류로 말한다.
  final String? message;

  const PostMediaFailure(this.kind, {this.message});

  /// 화면에 그대로 그리는 한 줄.
  String get label =>
      message ??
      switch (kind) {
        PostMediaFailureKind.network => '올리지 못했어요 · 연결을 확인해 주세요',
        PostMediaFailureKind.unauthorized => '로그인하면 올릴 수 있어요',
        PostMediaFailureKind.rateLimited => '잠시 후 다시 시도해 주세요',
        PostMediaFailureKind.rejected => '이 사진은 올릴 수 없어요',
        PostMediaFailureKind.notFound => '이미 지워진 사진이에요',
      };

  @override
  String toString() => 'PostMediaFailure($kind, $message)';
}

class PostMediaRepository {
  /// 업로드는 글 저장보다 오래 걸린다 — 수백 KB 를 카페 wifi 로 보낸다.
  static const Duration timeout = Duration(seconds: 30);

  /// 한 글에 붙일 수 있는 수. 서버 `PostRequest.MAX_MEDIA` 와 같은 값이다.
  static const int maxPerPost = 10;

  /// 서버 `POST_IMAGE` 의 상한. `ImagePrep` 을 지난 사진은 이보다 훨씬 작다.
  static const int maxBytes = 10 * 1024 * 1024;

  /// 서버가 받는 카테고리. 다른 셋은 감정 여행 시절 것이다.
  static const String category = 'POST_IMAGE';

  /// 아이 프로필 사진의 카테고리 (#448) — 서버의 `profiles/` 접두, 5MB 까지.
  static const String profileCategory = 'PROFILE_IMAGE';

  /// 채팅 말풍선 사진(#452) — 메시지에 하나씩 붙는다.
  static const String chatCategory = 'CHAT_IMAGE';

  /// S3 로 직접 올리는 시간. 720p 60초는 수십 MB 다 — 카페 wifi 로 몇 분이다.
  static const Duration videoPutTimeout = Duration(minutes: 5);

  final String baseUrl;
  final AuthedClient _authed;

  /// 토큰을 **안 붙이는** 길 — S3 서명 URL 로 갈 때만 쓴다.
  final http.Client _plain;

  PostMediaRepository({String? baseUrl, AuthedClient? client, http.Client? plainClient})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance,
        _plain = plainClient ?? http.Client();

  /// 한 장 올린다. `ImagePrep` 을 지난 JPEG 만 여기 온다 — 원본을 넣는 길은 없다.
  ///
  /// [width]·[height] 는 다시 인코딩한 뒤의 크기다. 피드가 이 값으로 자리를 미리 잡는다.
  Future<UploadedPostMedia> upload({
    required Uint8List jpegBytes,
    required int width,
    required int height,
    String filename = 'photo.jpg',
    String category = PostMediaRepository.category,
  }) async {
    if (jpegBytes.length > maxBytes) {
      throw const PostMediaFailure(PostMediaFailureKind.rejected,
          message: '사진이 너무 커요 · 10MB 까지 올릴 수 있어요');
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/media'))
      ..fields['category'] = category
      ..fields['width'] = '$width'
      ..fields['height'] = '$height'
      ..files.add(http.MultipartFile.fromBytes(
        'files',
        jpegBytes,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      ));

    final http.Response res;
    try {
      // 401 이면 AuthedClient 가 토큰을 갱신해 같은 요청을 다시 조립해 보낸다.
      final streamed = await _authed.send(request).timeout(timeout);
      res = await http.Response.fromStream(streamed);
    } catch (_) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }

    final body = _decode(res.bodyBytes);
    _throwIfFailed(res.statusCode, body);

    // 서버는 배열로 돌려준다 — 여러 장을 받는 경로라서. 우리는 한 장을 보냈다.
    final first = body is List && body.isNotEmpty ? UploadedPostMedia.tryParse(body.first) : null;
    if (first == null) throw const PostMediaFailure(PostMediaFailureKind.network);
    return first;
  }

  /// 올려 두고 안 쓸 것을 지운다. 글에 아직 안 붙은 것만 여기로 온다 — 붙은 것은 글 고치기가
  /// `mediaIds` 로 다룬다. 실패해도 큰일은 아니다: 하루 뒤 서버가 거둔다.
  Future<void> delete(int mediaId) async {
    final http.Response res;
    try {
      res = await _authed.deleteJson(Uri.parse('$baseUrl/media/$mediaId')).timeout(timeout);
    } catch (_) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }
    if (res.statusCode == 204) return;
    _throwIfFailed(res.statusCode, _decode(res.bodyBytes));
    throw const PostMediaFailure(PostMediaFailureKind.network);
  }

  // ─────────────────────────── 영상 — 세 단계 (#429, 서버 #435) ───────────────────────────

  /// 영상 하나를 세 단계로 올린다 — ① 자리 잡기 ② S3 에 직접 PUT ③ 포스터와 함께 끝내기.
  ///
  /// `VideoPrep` 을 지난 파일만 여기 온다 — 위치 상자가 덮인 720p 다. [onProgress] 는 ② 의
  /// 진행률(0..1)이다. 어느 단계에서 실패했든 다시 부르면 **처음부터**다 — 자리를 새로 잡는다.
  /// 남은 `pending` 자리는 하루 뒤 서버가 거둔다.
  Future<UploadedPostMedia> uploadVideo(
    PreparedVideo video, {
    void Function(double fraction)? onProgress,
  }) async {
    if (video.size > VideoLimits.maxBytes) {
      throw PostMediaFailure(PostMediaFailureKind.rejected,
          message: '영상이 너무 커요 · ${VideoLimits.maxBytes ~/ (1024 * 1024)}MB 까지 올릴 수 있어요');
    }
    final ticket = await _reserveVideo(video);
    await _putToS3(ticket.uploadUrl, video, onProgress);
    return _completeVideo(ticket.id, video.poster);
  }

  /// ① `POST /media/videos` — 계약 `VideoUploadRequest` 의 키 그대로. 크기를 모르면 `width`·
  /// `height` 를 안 싣는다(둘은 함께여야 한다).
  Future<VideoUploadTicket> _reserveVideo(PreparedVideo video) async {
    final http.Response res;
    try {
      res = await _authed.postJson(Uri.parse('$baseUrl/media/videos'), body: {
        'contentType': video.contentType,
        'size': video.size,
        if (video.width != null && video.height != null) ...{
          'width': video.width,
          'height': video.height,
        },
        'durationMs': video.durationMs,
      }).timeout(timeout);
    } catch (_) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }
    final body = _decode(res.bodyBytes);
    _throwIfFailed(res.statusCode, body);
    final ticket = VideoUploadTicket.tryParse(body);
    if (ticket == null) throw const PostMediaFailure(PostMediaFailureKind.network);
    return ticket;
  }

  /// ② 서명 URL 로 파일을 흘린다. **토큰을 안 붙인다.** 파일을 조각으로 읽어 보내므로 수십 MB 를
  /// 통째로 메모리에 올리지 않는다.
  Future<void> _putToS3(Uri uploadUrl, PreparedVideo video, void Function(double)? onProgress) async {
    final request = http.StreamedRequest('PUT', uploadUrl)
      // 서명에 묶인 값이다 — 다르면 S3 가 SignatureDoesNotMatch 로 거절한다.
      ..headers['Content-Type'] = video.contentType
      ..contentLength = video.size;
    unawaited(_feed(request, video, onProgress));

    final http.StreamedResponse res;
    try {
      res = await _plain.send(request).timeout(videoPutTimeout);
      await res.stream.drain<void>();
    } catch (_) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }
    if (res.statusCode == 403) {
      // 서명이 만료됐거나(15분) Content-Type 이 다르다. 다시 부르면 자리를 새로 잡는다.
      throw const PostMediaFailure(PostMediaFailureKind.rejected,
          message: '올리는 데 너무 오래 걸렸어요 · 다시 시도해 주세요');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }
  }

  static Future<void> _feed(
    http.StreamedRequest request,
    PreparedVideo video,
    void Function(double)? onProgress,
  ) async {
    var sent = 0;
    try {
      await for (final chunk in video.openRead()) {
        request.sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(video.size <= 0 ? 1 : (sent / video.size).clamp(0, 1).toDouble());
      }
    } catch (e, st) {
      request.sink.addError(e, st);
    } finally {
      await request.sink.close();
    }
  }

  /// ③ `POST /media/{id}/complete` — 포스터 한 장을 multipart 로. 서버가 S3 에 HEAD 로 확인하고
  /// `ready` 로 바꾼다. 409 는 "아직 S3 에 없다" — 서버 문구를 그대로 든다.
  Future<UploadedPostMedia> _completeVideo(int id, Uint8List poster) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/media/$id/complete'))
      ..files.add(http.MultipartFile.fromBytes(
        'poster',
        poster,
        filename: 'poster.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    final http.Response res;
    try {
      final streamed = await _authed.send(request).timeout(timeout);
      res = await http.Response.fromStream(streamed);
    } catch (_) {
      throw const PostMediaFailure(PostMediaFailureKind.network);
    }
    final body = _decode(res.bodyBytes);
    _throwIfFailed(res.statusCode, body);
    final item = UploadedPostMedia.tryParse(body);
    if (item == null) throw const PostMediaFailure(PostMediaFailureKind.network);
    return item;
  }

  /// 상태 코드를 실패의 종류로 옮기는 곳은 여기 하나다.
  static void _throwIfFailed(int status, Object? body) {
    if (status >= 200 && status < 300) return;
    final message = _messageOf(body);
    throw switch (status) {
      400 => PostMediaFailure(PostMediaFailureKind.rejected, message: message),
      401 => const PostMediaFailure(PostMediaFailureKind.unauthorized),
      404 => PostMediaFailure(PostMediaFailureKind.notFound, message: message),
      // 아직 그 상태가 아니다(영상이 S3 에 없다). 서버가 이유를 준다 — 다시 시도하면 자리를 새로 잡는다.
      409 => PostMediaFailure(PostMediaFailureKind.rejected, message: message),
      429 => const PostMediaFailure(PostMediaFailureKind.rateLimited),
      _ => const PostMediaFailure(PostMediaFailureKind.network),
    };
  }

  static Object? _decode(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String? _messageOf(Object? body) {
    if (body is Map && body['error'] is Map) {
      final message = (body['error'] as Map)['message'];
      return message is String && message.isNotEmpty ? message : null;
    }
    return null;
  }
}

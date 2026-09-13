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
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';

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

  final String baseUrl;
  final AuthedClient _authed;

  PostMediaRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance;

  /// 한 장 올린다. `ImagePrep` 을 지난 JPEG 만 여기 온다 — 원본을 넣는 길은 없다.
  ///
  /// [width]·[height] 는 다시 인코딩한 뒤의 크기다. 피드가 이 값으로 자리를 미리 잡는다.
  Future<UploadedPostMedia> upload({
    required Uint8List jpegBytes,
    required int width,
    required int height,
    String filename = 'photo.jpg',
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

  /// 상태 코드를 실패의 종류로 옮기는 곳은 여기 하나다.
  static void _throwIfFailed(int status, Object? body) {
    if (status >= 200 && status < 300) return;
    final message = _messageOf(body);
    throw switch (status) {
      400 => PostMediaFailure(PostMediaFailureKind.rejected, message: message),
      401 => const PostMediaFailure(PostMediaFailureKind.unauthorized),
      404 => PostMediaFailure(PostMediaFailureKind.notFound, message: message),
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

// 글에 붙은 사진·영상 하나 — 계약의 `PostMedia`. 이슈 #429, 서버는 PR #430.
//
// ## 키는 서버 레코드에서 옮겨 적었다
//
// `PostResponse.PostMedia(id, kind, url, posterUrl, width, height, durationMs)` 그대로다.
// 앱이 읽는 키를 보고 목을 만들면 테스트가 버그에 동의한다 — 채팅에서 `messages` 와
// `items` 가 갈렸던 그 일이다. 파서 테스트는 이 키들만 넣은 응답으로 잰다.
//
// ## 모르는 종류는 버린다
//
// 서버가 언젠가 `kind` 를 늘리면(예: 문서) 그 항목은 목록에서 빠진다. 사진으로 그리면
// 영상 URL 을 그림으로 열려다 깨진 칸이 뜨고, 영상으로 그리면 재생을 시도한다. 한 칸이
// 이상해도 나머지는 산다 — `Crew.parseList` 와 같은 규칙이다.
import 'package:flutter/foundation.dart';

/// 화면이 그리는 종류. 서버의 카테고리(`POST_IMAGE`·`POST_VIDEO`)에서 온다.
enum PostMediaKind {
  image('image'),
  video('video');

  const PostMediaKind(this.wire);

  /// 계약의 값.
  final String wire;

  bool get isVideo => this == PostMediaKind.video;

  /// 모르는 값이면 `null` — 부르는 쪽이 그 항목을 버린다.
  static PostMediaKind? tryParse(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

@immutable
class PostMedia {
  final int id;
  final PostMediaKind kind;

  /// CDN 공개 URL. 사진이면 그림, 영상이면 재생할 파일.
  final String url;

  /// 영상의 썸네일. 사진은 `null`.
  final String? posterUrl;

  /// 픽셀 폭·높이. 앱이 올릴 때 준 값이라 없을 수 있다 — 그러면 정사각형 자리를 잡는다.
  final int? width;
  final int? height;

  /// 영상 길이. 사진은 `null`.
  final int? durationMs;

  const PostMedia({
    required this.id,
    required this.kind,
    required this.url,
    this.posterUrl,
    this.width,
    this.height,
    this.durationMs,
  });

  /// 피드 카드에서 허용하는 가장 세로인 비율 — **4:5**(#440).
  ///
  /// 인스타그램(피드 1.91:1 ~ 4:5, 그보다 세로면 4:5 로 자름) · 페이스북(단일 사진 4:5 상한,
  /// 릴스도 피드에서는 4:5) · 레딧(4:5 보다 세로면 피드에서 자르고 "See full image") 이 같은
  /// 답이다. 세로 영상 포스터(9:16)를 원본 비율로 두면 360dp 폰에서 사진만 640dp 라 카드가
  /// 한 화면에 안 들어온다 — 사장님이 짚은 것이 그것이다. 전체 보기는 원본 그대로다.
  static const double minFeedAspectRatio = 4 / 5;

  /// 가장 가로인 비율 — 인스타그램의 1.91:1 그대로. 파노라마는 가운데를 보여 준다.
  static const double maxFeedAspectRatio = 1.91;

  /// 서버가 가로세로를 아는가. 모르면 카드가 자리를 **1:1 로 잡고**, 그 자리에 4:5 사진을
  /// [BoxFit.cover] 로 그리면 위아래가 잘린다 — 산책 경로 그림(1080×1350)의 아래쪽
  /// "0.90km · 01:13" 이 실제로 그렇게 잘렸다(#517). 모를 때는 카드가 안 자른다.
  bool get hasSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  /// 카드에서 자리를 잡을 가로세로비. 크기를 모르면 1 이다 — 사진이 도착할 때마다 화면이
  /// 뛰지 않게 **미리** 잡는 것이 이 값의 목적이다. [minFeedAspectRatio]~[maxFeedAspectRatio]
  /// 밖은 그 끝으로 잘라 카드 안에서 가운데를 그린다(`BoxFit.cover`) — 크기를 **알 때만**
  /// 그렇게 한다([hasSize]).
  double get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 1;
    return (w / h).clamp(minFeedAspectRatio, maxFeedAspectRatio).toDouble();
  }

  /// 카드에 그릴 그림. 영상이면 썸네일이고, 썸네일이 없으면 `null` — 그때는 어두운 칸이다.
  String? get thumbnailUrl => kind.isVideo ? posterUrl : url;

  /// 영상 길이 표시 — `0:08` · `1:00`. 사진이거나 길이를 모르면 `null`.
  String? get durationLabel {
    final ms = durationMs;
    if (!kind.isVideo || ms == null || ms < 0) return null;
    return formatMediaDuration(ms);
  }

  /// 모양이 아니면 `null`. 한 칸이 깨졌다고 글 전체를 버리지 않는다.
  static PostMedia? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = PostMediaKind.tryParse(json['kind']);
    final url = json['url'];
    if (id is! num || kind == null || url is! String || url.isEmpty) return null;
    return PostMedia(
      id: id.toInt(),
      kind: kind,
      url: url,
      posterUrl: _text(json['posterUrl']),
      width: _int(json['width']),
      height: _int(json['height']),
      durationMs: _int(json['durationMs']),
    );
  }

  static List<PostMedia> parseList(Object? json) {
    if (json is! List) return const [];
    return [
      for (final raw in json)
        if (PostMedia.tryParse(raw) case final media?) media,
    ];
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  @override
  bool operator ==(Object other) =>
      other is PostMedia &&
      other.id == id &&
      other.kind == kind &&
      other.url == url &&
      other.posterUrl == posterUrl &&
      other.width == width &&
      other.height == height &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(id, kind, url, posterUrl, width, height, durationMs);
}

/// `m:ss`. 내림이다 — 7.9초는 `0:07` 이다. 올림이면 59.1초짜리가 `1:00` 이 되어 60초 상한을
/// 넘는 것처럼 보인다.
String formatMediaDuration(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

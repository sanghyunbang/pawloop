// 올리기 전에 영상을 다시 인코딩하고 위치 상자를 덮는다 — 이슈 #429.
//
// ## 두 단계다 — 네이티브 재인코딩, 그리고 순수 Dart 덮기
//
// 1. `video_compress` 가 720p 로 다시 인코딩한다(네이티브 코덱). 100MB 문제가 여기서 풀리고,
//    대개 메타데이터도 옮겨 적지 않는다 — 그런데 "대개" 를 테스트로 잴 수가 없다. 플랫폼 채널이라
//    `flutter test` 에서 안 돈다.
// 2. 그래서 나온 파일을 [Mp4MetadataScrubber] 가 한 번 더 지난다 — `moov` 의 `udta`·`meta` 를
//    제자리에서 덮고, 다시 훑어 위치의 흔적이 **하나라도 남으면 올리지 않는다.** 이 둘째 단계는
//    순수 Dart 라 `video_prep_test`·`mp4_metadata_scrubber_test` 가 바이트로 잰다. 사진의
//    `ImagePrep` 과 같은 자리다.
//
// ## 길이는 재인코딩 전에 잰다
//
// 60초 넘는 영상을 1분 동안 압축한 뒤 "너무 길어요" 라고 하면 그 1분이 헛수고다. 먼저 묻고 넘으면
// 거기서 멈춘다. 크기(150MB)는 압축 **뒤**의 파일로 잰다 — 서버가 받는 것이 그 파일이다.
//
// ## 네이티브는 인터페이스 뒤에
//
// [VideoTranscoder] 가 그 자리다. 테스트는 픽스처 MP4 를 복사해 주는 가짜를 꽂아 **덮기와 확인이
// 진짜로 도는지**를 잰다. `MediaPicker` 를 인터페이스 뒤에 둔 것과 같은 판단이다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:video_compress/video_compress.dart';

import 'mp4_metadata_scrubber.dart';

/// 서버와 같은 상한 — 계약 `/media/videos`. 여기와 서버가 갈리면 사용자가 압축까지 기다린 뒤
/// 400 을 본다.
class VideoLimits {
  const VideoLimits._();

  static const Duration maxDuration = Duration(seconds: 60);
  static const int maxBytes = 150 * 1024 * 1024;

  /// 한 글에 영상 하나. 서버 `MediaService.MAX_VIDEOS_PER_POST` 와 같다.
  static const int maxPerPost = 1;
}

/// 재인코더가 파일에 대해 아는 것. 모르는 값은 `null`.
@immutable
class VideoProbe {
  final int? width;
  final int? height;
  final int? durationMs;
  final int? size;

  const VideoProbe({this.width, this.height, this.durationMs, this.size});

  /// 폭·높이를 **포스터의 방향**에 맞춘다.
  ///
  /// 폰으로 세로로 찍은 영상은 픽셀은 가로(1280×720)인데 회전 표시로 "세로로 보여라" 고 적혀
  /// 있다. 재인코더가 알려 주는 크기는 이 회전을 어떻게 셈했는지가 플랫폼·버전마다 다르다 —
  /// `video_compress` 3.1.4 의 Android 는 회전이 0 일 때 폭·높이를 바꿔 주는 반대 규칙이라,
  /// 에뮬레이터에서 세로 영상이 피드에 16:9 로 잡혔다. 그 값을 해석하지 않는다. 대신 포스터는
  /// 프레임 추출기가 회전을 **굽고** 낸 그림이라 방향이 화면과 같다 — 포스터가 세로인데 크기가
  /// 가로면 바꾼다. 피드가 자리를 잡는 것도 결국 그 포스터다.
  static (int?, int?) sizeMatchingPoster(int? width, int? height, (int, int)? poster) {
    if (width == null || height == null || poster == null) return (width, height);
    final (pw, ph) = poster;
    final posterPortrait = ph > pw;
    final sizePortrait = height > width;
    if (pw == ph || width == height || posterPortrait == sizePortrait) return (width, height);
    return (height, width);
  }
}

/// 네이티브 재인코더의 자리. 테스트가 가짜를 꽂는다.
abstract class VideoTranscoder {
  Future<VideoProbe> probe(String path);

  /// 720p 로 다시 인코딩한 **새 파일**의 경로. 원본은 안 건드린다.
  Future<String> transcode(String path);

  /// 첫 장면의 JPEG. 못 만들면 `null`.
  Future<Uint8List?> poster(String path);
}

/// `video_compress` 로.
class VideoCompressTranscoder implements VideoTranscoder {
  const VideoCompressTranscoder();

  @override
  Future<VideoProbe> probe(String path) async {
    final info = await VideoCompress.getMediaInfo(path);
    return VideoProbe(
      width: info.width,
      height: info.height,
      durationMs: info.duration?.round(),
      size: info.filesize,
    );
  }

  @override
  Future<String> transcode(String path) async {
    final info = await VideoCompress.compressVideo(
      path,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final out = info?.path;
    if (out == null || out.isEmpty) {
      throw const VideoPrepException('영상을 압축하지 못했어요');
    }
    return out;
  }

  @override
  Future<Uint8List?> poster(String path) => VideoCompress.getByteThumbnail(path, quality: 60, position: -1);
}

/// 다시 인코딩하고 덮은 결과. 이것만 서버로 간다.
@immutable
class PreparedVideo {
  /// 720p 파일. 올리고 나서 지운다.
  final String path;

  /// 바이트 수 — 서버에 알리는 값이고, `complete` 가 실제 크기와 대조한다.
  final int size;

  final int? width;
  final int? height;
  final int durationMs;

  /// 앱이 뽑은 썸네일(JPEG). `complete` 에 싣는다.
  final Uint8List poster;

  final String contentType;

  /// 파일을 읽는 길. 기본은 [path] 를 여는 것이다 — 위젯 테스트는 가짜 시계 안에서 파일 IO 가
  /// 안 끝나므로 메모리에서 흘리는 함수를 꽂는다.
  final Stream<List<int>> Function()? source;

  const PreparedVideo({
    required this.path,
    required this.size,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.poster,
    this.contentType = 'video/mp4',
    this.source,
  });

  /// 올릴 바이트를 조각으로. 수십 MB 를 통째로 메모리에 올리지 않는다.
  Stream<List<int>> openRead() => (source ?? () => File(path).openRead())();

  /// 720p 파일을 지운다 — 올라갔거나 떼어 냈을 때. 없어도, 못 지워도 그만이다(캐시 폴더다).
  Future<void> discard() async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}

/// 이 영상은 못 올린다. 화면이 그 칸에 이유를 쓴다.
class VideoPrepException implements Exception {
  final String message;
  const VideoPrepException(this.message);

  @override
  String toString() => 'VideoPrepException($message)';
}

/// [VideoPrep.prepare] 와 같은 모양. 화면과 테스트가 이 타입으로 주입받는다.
typedef VideoPreparer = Future<PreparedVideo> Function(String path);

class VideoPrep {
  final VideoTranscoder transcoder;
  final int maxBytes;
  final Duration maxDuration;

  const VideoPrep({
    this.transcoder = const VideoCompressTranscoder(),
    this.maxBytes = VideoLimits.maxBytes,
    this.maxDuration = VideoLimits.maxDuration,
  });

  /// 기본 배선 — 화면이 쓴다.
  static Future<PreparedVideo> prepare(String path) => const VideoPrep().run(path);

  /// 포스터 JPEG 의 픽셀 크기. 헤더만 읽는다 — 그림을 다 풀지 않는다. 못 읽으면 `null`.
  static (int, int)? posterSize(Uint8List poster) {
    try {
      final info = img.JpegDecoder().startDecode(poster);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return (info.width, info.height);
    } catch (_) {
      return null;
    }
  }

  /// 길이 검사 → 720p → 덮기 → 확인 → 크기 검사 → 포스터.
  Future<PreparedVideo> run(String path) async {
    final VideoProbe original;
    try {
      original = await transcoder.probe(path);
    } catch (_) {
      throw const VideoPrepException('영상을 읽을 수 없어요');
    }
    final originalMs = original.durationMs;
    if (originalMs == null || originalMs <= 0) {
      throw const VideoPrepException('영상 길이를 읽을 수 없어요');
    }
    if (originalMs > maxDuration.inMilliseconds) {
      throw VideoPrepException('영상은 ${maxDuration.inSeconds}초까지 올릴 수 있어요');
    }

    final out = await transcoder.transcode(path);

    // **여기가 요점이다.** 재인코더가 무엇을 남겼든 위치 상자는 덮이고, 남은 흔적이 있으면 안 나간다.
    try {
      await Mp4MetadataScrubber.scrubFile(out);
    } on Mp4FormatException {
      throw const VideoPrepException('영상 파일을 읽을 수 없어요');
    }
    final traces = await Mp4MetadataScrubber.findLocationTracesInFile(out);
    if (traces.isNotEmpty) {
      throw const VideoPrepException('위치 정보를 지우지 못해서 올리지 않아요');
    }

    final size = await File(out).length();
    if (size > maxBytes) {
      throw VideoPrepException('영상이 너무 커요 · ${maxBytes ~/ (1024 * 1024)}MB 까지 올릴 수 있어요');
    }

    // 서버에 알리는 크기·길이는 **나가는 파일**의 것이다 — 720p 로 줄었으니 원본과 다르다.
    VideoProbe compressed;
    try {
      compressed = await transcoder.probe(out);
    } catch (_) {
      compressed = const VideoProbe();
    }
    final poster = await transcoder.poster(out);
    if (poster == null || poster.isEmpty) {
      throw const VideoPrepException('썸네일을 만들지 못했어요');
    }
    // 방향은 포스터를 따른다 — 피드가 자리를 잡는 그림이 그것이다.
    final (width, height) =
        VideoProbe.sizeMatchingPoster(compressed.width, compressed.height, posterSize(poster));

    return PreparedVideo(
      path: out,
      size: size,
      width: width,
      height: height,
      durationMs: compressed.durationMs ?? originalMs,
      poster: poster,
    );
  }
}

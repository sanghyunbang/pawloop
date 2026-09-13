// 올리기 전에 사진을 다시 인코딩한다 — 이슈 #429.
//
// ## 여기가 위치 정보가 빠지는 자리다
//
// 폰 카메라는 EXIF 에 촬영 좌표(GPS IFD)를 넣는다. 그대로 올리면 좌표가 단말을 떠난다 —
// #235 A안이 막은 바로 그것이고, 커뮤니티 사진 한 장으로 남의 집 앞 좌표가 새는 문제이기도
// 하다. 그래서 **지우는 것이 아니라 처음부터 안 싣는다** — 픽셀만 들어 새 JPEG 를 만든다.
//
// `image` 패키지의 JPEG 인코더는 `image.exif` 가 비어 있지 않으면 **EXIF 를 그대로 써 넣는다**
// (`JpegEncoder._writeExif`). 디코드→인코드만으로는 GPS 가 살아남는다. 그래서 인코딩 직전에
// `exif` 를 새 `ExifData()` 로 갈아 끼운다. `image_prep_test.dart` 가 GPS 를 실은 JPEG 를
// 넣어 나간 바이트에 GPS IFD 가 없는지 **값으로** 잰다 — 이 줄을 빼면 빨간불이다.
//
// ## 순수 Dart 인 이유
//
// 네이티브 압축 플러그인이 더 빠르지만 `flutter test` 에서 안 돈다(플랫폼 채널). 그러면 위의
// 값 테스트를 CI 에서 못 돌린다. 이 파일은 `compute` 로 격리 스레드에서 돌아 화면을 안 막고,
// 12MP 사진 한 장에 폰에서 1~3초쯤이다. 더 빨라야 하는 날 같은 인터페이스 뒤에 네이티브를
// 꽂되 **이 테스트는 그대로 둔다.**
//
// ## 회전은 EXIF 를 버리기 전에 픽셀에 굽는다
//
// 폰 사진은 픽셀은 가로인데 EXIF 의 orientation 으로 "세로로 보여라" 고 적힌 경우가 많다.
// EXIF 를 버리면 그 지시도 사라지니 그 전에 픽셀을 실제로 돌려야 한다 — 안 그러면 올린 사진이
// 누워 있다. `image` 의 JPEG 디코더는 **디코드하면서 이미 굽는다**(`_jpeg_quantize_io.dart`,
// 굽고 나서 orientation 태그를 지운다). 아래 `bakeOrientation` 은 다른 형식(PNG 의 eXIf 등)을
// 위한 한 번 더이고, 이미 구운 JPEG 에는 아무 일도 안 한다. `image_prep_test` 는 "나간 사진이
// 바로 서 있다" 를 잰다 — 누가 굽는지가 아니라 결과를.
//
// ## `UPLOAD_LOCATION` 과 무관하다
//
// `LocationUploadPolicy` 를 지나지 않는다. 산책 경로 전송을 켠 빌드에서도 사진의 좌표는
// 안 나간다 — 게이트가 아니라 경로 자체가 없다(`legal-lbs-compliance.md` §7).
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 다시 인코딩한 결과. 크기는 서버에 함께 보낸다 — 피드가 자리를 미리 잡는다.
@immutable
class PreparedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const PreparedImage({required this.bytes, required this.width, required this.height});
}

/// 사진을 못 읽었다. 화면은 그 칸에 "이 사진은 읽을 수 없어요" 를 그린다.
class ImagePrepException implements Exception {
  final String message;
  const ImagePrepException(this.message);

  @override
  String toString() => 'ImagePrepException($message)';
}

/// [ImagePrep.prepare] 와 같은 모양. 테스트와 화면이 이 타입으로 주입받는다.
typedef ImagePreparer = Future<PreparedImage> Function(Uint8List original);

class ImagePrep {
  const ImagePrep._();

  /// 긴 변의 상한. 피드 카드와 상세에는 충분하고, 서버 상한(10MB)에 넉넉히 든다 —
  /// 1600px JPEG 는 대개 수백 KB 다.
  static const int maxLongEdge = 1600;

  /// JPEG 품질. 85 는 눈으로 차이가 안 나는 선에서 파일이 절반쯤 되는 값이다.
  static const int jpegQuality = 85;

  /// 격리 스레드에서 [prepareSync] 를 돈다. 화면이 안 멈춘다.
  static Future<PreparedImage> prepare(Uint8List original) =>
      compute(prepareSync, original);

  /// 디코드 → 회전 굽기 → 긴 변 1600 이하로 줄이기 → **EXIF 없는** JPEG.
  ///
  /// 동기다 — `compute` 가 부르고, 테스트는 바로 부른다.
  static PreparedImage prepareSync(Uint8List original) {
    // 형식을 못 알아보면 null 이지만, 형식은 맞는데 속이 깨진 파일은 디코더가 예외를 던진다.
    // 둘 다 같은 답이다 — 이 사진은 못 쓴다.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(original);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const ImagePrepException('사진을 읽을 수 없어요');
    }

    // orientation 이 남아 있으면 픽셀에 굽는다. EXIF 를 버리기 **전**이어야 한다.
    // (JPEG 는 디코더가 이미 구웠으니 여기서는 no-op — 위 주석.)
    final baked = img.bakeOrientation(decoded);

    final longEdge = math.max(baked.width, baked.height);
    final img.Image sized;
    if (longEdge > maxLongEdge) {
      final scale = maxLongEdge / longEdge;
      sized = img.copyResize(
        baked,
        width: math.max(1, (baked.width * scale).round()),
        height: math.max(1, (baked.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    } else {
      sized = baked;
    }

    // **여기가 요점이다.** 인코더가 exif 를 그대로 쓰므로 통째로 비운다 — GPS 도 함께.
    sized.exif = img.ExifData();

    final bytes = img.encodeJpg(sized, quality: jpegQuality, chroma: img.JpegChroma.yuv420);
    return PreparedImage(bytes: bytes, width: sized.width, height: sized.height);
  }
}

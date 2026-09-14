// 기기에서 사진을 고른다 — 이슈 #429.
//
// `image_picker` 를 인터페이스 뒤에 둔다. 위젯 테스트는 플랫폼 채널이 없어 진짜 고르기를
// 못 띄우므로 가짜를 꽂는다 — `MediaPicker` 가 그 자리다. `walk_dog_picker` 가 반려 프로필을
// 받는 것과 같은 판단이다.
//
// ## 갤러리 + 카메라
//
// 글 사진은 갤러리에서 고르고(#429), 산책 중 사진은 카메라로 찍는다(#450, `takePhoto`).
// 카메라를 열면 iOS 에 `NSCameraUsageDescription` 이 있어야 하고, 없으면 누르는 순간 앱이
// 죽는다 — #450 에서 그 문구를 함께 넣었다.
//
// ## `requestFullMetadata: false`
//
// iOS 에서 사진의 전체 메타데이터(위치 포함)를 요청하지 않는다. 진짜로 지우는 것은
// `ImagePrep` 이 다시 인코딩할 때다 — 이건 그 앞의 안전벨트 하나다.
//
// ## 영상은 파일로 든다
//
// 사진은 바이트로 받아 바로 다시 인코딩하지만, 영상은 수십 MB 라 경로만 든다. `VideoPrep` 이
// 그 경로로 720p 파일을 새로 만들고 그것을 흘려 보낸다. `maxDuration` 은 OS 고르기에 주는
// **힌트**다(iOS 는 자르기를 권하고 Android 는 대개 무시한다) — 판정은 `VideoPrep` 이 한다.

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'video_prep.dart' show VideoLimits;

/// 고른 사진 하나 — 아직 서버에 없다.
@immutable
class PickedImage {
  /// 원래 파일 이름. 서버에 보내는 이름의 재료일 뿐 저장되는 값이 아니다.
  final String name;

  /// 원본 바이트. `ImagePrep` 이 이것을 받아 다시 인코딩한다.
  final Uint8List bytes;

  const PickedImage({required this.name, required this.bytes});
}

/// 고른 영상 하나 — 파일 경로로 든다. 아직 서버에 없다.
@immutable
class PickedVideo {
  final String name;

  /// 기기 안의 원본 경로. `VideoPrep` 이 여기서 읽어 새 파일을 만든다 — 원본은 안 건드린다.
  final String path;

  const PickedVideo({required this.name, required this.path});
}

abstract class MediaPicker {
  /// 갤러리에서 사진을 고른다. 사용자가 닫으면 빈 목록이다.
  ///
  /// [limit] 은 남은 자리다. 서버가 한 글에 열 장까지 받는다.
  Future<List<PickedImage>> pickImages({required int limit});

  /// 갤러리에서 영상 하나를 고른다. 사용자가 닫으면 `null`.
  Future<PickedVideo?> pickVideo();

  /// 카메라로 한 장 찍는다 — 산책 중 사진(#450). 사용자가 닫으면 `null`.
  ///
  /// iOS 는 `NSCameraUsageDescription` 이 있어야 한다(`ios/Runner/Info.plist`) — 없으면 누르는
  /// 순간 앱이 죽는다. 촬영 좌표는 `ImagePrep` 이 다시 인코딩할 때 빠진다.
  Future<PickedImage?> takePhoto();
}

class ImagePickerMediaPicker implements MediaPicker {
  final ImagePicker _picker;

  ImagePickerMediaPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  @override
  Future<List<PickedImage>> pickImages({required int limit}) async {
    if (limit <= 0) return const [];

    // `pickMultiImage` 는 limit 이 2 이상이어야 한다(플러그인이 단언한다). 한 자리 남았을
    // 때는 한 장 고르기로 간다 — 그러지 않으면 마지막 한 장에서 예외가 난다.
    final List<XFile> files;
    if (limit == 1) {
      final one = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      files = one == null ? const [] : [one];
    } else {
      files = await _picker.pickMultiImage(limit: limit, requestFullMetadata: false);
    }

    return [
      for (final file in files.take(limit))
        PickedImage(name: file.name, bytes: await file.readAsBytes()),
    ];
  }

  @override
  Future<PickedVideo?> pickVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: VideoLimits.maxDuration,
    );
    if (file == null) return null;
    return PickedVideo(name: file.name, path: file.path);
  }

  @override
  Future<PickedImage?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return PickedImage(name: file.name, bytes: await file.readAsBytes());
  }
}

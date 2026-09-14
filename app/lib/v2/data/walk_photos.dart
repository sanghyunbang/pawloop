// 산책 중 찍은 사진 — 이슈 #450.
//
// ## 두 자리
//
// - `WalkPhotoStore`: 찍은 바이트를 **앱 문서 폴더**의 파일로 둔다. 카메라가 준 파일은 캐시 폴더라
//   OS 가 언제든 지우고, 산책은 한 시간을 넘기도 한다. 경로는 진행 중 스냅숏(`WalkInProgress`)과
//   초안(`WalkDraft`)에 실려 앱이 죽어도 · 오프라인이어도 살아남는다.
// - `WalkPhotoUploader`: 저장할 때 경로를 읽어 `ImagePrep` 으로 다시 인코딩(위치 정보 제거 · 긴 변
//   제한)하고 `POST /media`(WALK_IMAGE) 로 올린다. 글 사진(#429)과 같은 길이고 붙이기만 산책이다.
//
// 산책이 서버에 저장되면 파일은 지운다 — 서버가 정본이다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'image_prep.dart';
import 'post_media_repository.dart';

class WalkPhotoStore {
  /// 산책 사진이 사는 폴더 이름 — 문서 폴더 아래.
  static const String folder = 'walk_photos';

  final Future<Directory> Function() _root;

  const WalkPhotoStore({Future<Directory> Function()? root}) : _root = root ?? _documents;

  static Future<Directory> _documents() => getApplicationDocumentsDirectory();

  /// 찍은 바이트를 파일로 두고 경로를 돌려준다. [walkKey] 는 산책 하나의 이름(시작 시각 등).
  Future<String> save(String walkKey, Uint8List bytes) async {
    final dir = Directory('${(await _root()).path}${Platform.pathSeparator}$folder'
        '${Platform.pathSeparator}${_safe(walkKey)}');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 서버에 붙은 뒤(또는 버린 뒤) 파일을 지운다. 없으면 없는 대로 — 이미 지웠거나 OS 가 지운 것이다.
  Future<void> discard(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 못 지운 파일은 다음 산책 때 폴더째 정리된다 — 화면을 세울 일이 아니다.
      }
    }
  }

  /// 찍어 둔 파일을 읽는다 — 없어졌으면(OS 가 지웠거나 옮겼으면) null. 끝내기 시트의 띠와 공유 카드가 쓴다:
  /// 시트 파일엔 `dart:io` 가 못 들어온다(#310 소스 잠금).
  Future<Uint8List?> read(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static String _safe(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

/// 경로 하나 → 서버의 media id. 테스트가 가짜를 꽂는 자리.
typedef WalkPhotoUpload = Future<int> Function(String path);

class WalkPhotoUploader {
  /// `POST /media` 의 category — 서버의 `UploadCategory.WALK_IMAGE`.
  static const String category = 'WALK_IMAGE';

  final PostMediaRepository _media;
  final Future<PreparedImage> Function(Uint8List original) _prepare;

  WalkPhotoUploader({
    PostMediaRepository? media,
    Future<PreparedImage> Function(Uint8List original) prepare = ImagePrep.prepare,
  })  : _media = media ?? PostMediaRepository(),
        _prepare = prepare;

  /// 읽고 → 다시 인코딩하고 → 올린다. 실패는 [PostMediaFailure] 그대로 — 부르는 쪽(`WalkSync`)이
  /// 다시 보낼지(연결) 버릴지(거절) 가른다.
  Future<int> upload(String path) async {
    final bytes = await File(path).readAsBytes();
    final prepared = await _prepare(bytes);
    final uploaded = await _media.upload(
      jpegBytes: prepared.bytes,
      width: prepared.width,
      height: prepared.height,
      filename: 'walk.jpg',
      category: category,
    );
    return uploaded.id;
  }
}

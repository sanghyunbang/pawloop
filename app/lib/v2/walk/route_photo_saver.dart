// lib/v2/walk/route_photo_saver.dart
//
// 경로 사진을 **기기 갤러리에만** 저장한다 — 이슈 #310. 업로드 경로를 타지 않는다.
//
// `gal` 은 안드로이드 10+ 에서 권한 없이 MediaStore 로 넣고, 그 아래(API 29 이하)에서는
// WRITE_EXTERNAL_STORAGE 를 쓴다(매니페스트에 maxSdkVersion 29 로 적었다). iOS 는
// NSPhotoLibraryAddUsageDescription 이 필요하다 — Info.plist 참조.
//
// 이 파일에는 네트워크 클라이언트가 없다. `route_photo_no_network_test.dart` 가 그것을 잠근다.
import 'dart:typed_data';

import 'package:gal/gal.dart';

/// 저장이 안 된 이유 — 화면이 문구를 고르는 데 쓴다.
enum RoutePhotoFailure {
  /// 사용자가 사진 접근을 거절했다(iOS · 옛 안드로이드). 설정에서 켜야 한다.
  permissionDenied,

  /// 그 밖의 실패 — 저장 공간, 플랫폼 오류.
  other,
}

class RoutePhotoException implements Exception {
  final RoutePhotoFailure kind;
  const RoutePhotoException(this.kind);

  String get message => switch (kind) {
        RoutePhotoFailure.permissionDenied => '사진 저장 권한이 없어요 · 설정에서 허용해 주세요',
        RoutePhotoFailure.other => '사진을 저장하지 못했어요',
      };

  @override
  String toString() => 'RoutePhotoException($kind)';
}

/// 갤러리에 PNG 를 넣는 일. 테스트가 가짜를 꽂을 수 있게 함수 하나로 좁혔다.
class RoutePhotoSaver {
  final Future<void> Function(Uint8List bytes, String name) _put;

  const RoutePhotoSaver._(this._put);

  /// 운영 — `gal` 로 갤러리 앨범 "Pawloop" 에 넣는다.
  factory RoutePhotoSaver.gallery() => RoutePhotoSaver._((bytes, name) async {
        try {
          await Gal.putImageBytes(bytes, name: name, album: 'Pawloop');
        } on GalException catch (e) {
          throw RoutePhotoException(
            e.type == GalExceptionType.accessDenied
                ? RoutePhotoFailure.permissionDenied
                : RoutePhotoFailure.other,
          );
        }
      });

  /// 테스트 — 받은 바이트를 붙잡아 둔다.
  factory RoutePhotoSaver.fake(Future<void> Function(Uint8List bytes, String name) put) =>
      RoutePhotoSaver._(put);

  Future<void> save(Uint8List png, {required DateTime walkedAt}) =>
      _put(png, 'pawloop_walk_${_stamp(walkedAt)}');

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  }
}

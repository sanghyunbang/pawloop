// 위젯 테스트용 고르기 — 갤러리 대신 주어진 것을 돌려준다.
import 'package:heat_trip_flutter/v2/data/media_picker.dart';

class FakeMediaPicker implements MediaPicker {
  /// 남은 자리(limit)를 받아 고른 사진을 돌려준다.
  final List<PickedImage> Function(int limit) supply;

  /// 고른 영상. 없으면(기본) 고르기를 닫은 것이다.
  final PickedVideo? Function()? supplyVideo;

  int calls = 0;
  int videoCalls = 0;
  int? lastLimit;

  FakeMediaPicker(this.supply, {this.supplyVideo, this.supplyShot});

  @override
  Future<List<PickedImage>> pickImages({required int limit}) async {
    calls++;
    lastLimit = limit;
    return supply(limit);
  }

  @override
  Future<PickedVideo?> pickVideo() async {
    videoCalls++;
    return supplyVideo?.call();
  }

  /// 카메라로 찍은 것. 없으면(기본) 카메라를 닫은 것이다 (#450).
  final PickedImage? Function()? supplyShot;
  int shotCalls = 0;

  @override
  Future<PickedImage?> takePhoto() async {
    shotCalls++;
    return supplyShot?.call();
  }
}

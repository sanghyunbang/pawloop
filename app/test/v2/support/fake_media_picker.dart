// 위젯 테스트용 사진 고르기 — 갤러리 대신 주어진 바이트를 돌려준다.
import 'package:heat_trip_flutter/v2/data/media_picker.dart';

class FakeMediaPicker implements MediaPicker {
  /// 남은 자리(limit)를 받아 고른 사진을 돌려준다.
  final List<PickedImage> Function(int limit) supply;

  int calls = 0;
  int? lastLimit;

  FakeMediaPicker(this.supply);

  @override
  Future<List<PickedImage>> pickImages({required int limit}) async {
    calls++;
    lastLimit = limit;
    return supply(limit);
  }
}

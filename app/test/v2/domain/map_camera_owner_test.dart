// 지도 카메라를 누가 쥐고 있나 (#769) — 늦게 온 위치가 사용자의 확대를 덮던 자리의 규칙.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/map_camera_owner.dart';

void main() {
  test('아무도 안 만졌으면 앱이 옮긴다 — 처음 자리잡기는 그대로 된다', () {
    final camera = MapCameraOwner();

    expect(camera.userMoved, isFalse);
    expect(camera.mayAutoMove, isTrue);
  });

  test('사용자가 손으로 옮기면 앱은 더 이상 안 옮긴다 — 늦게 온 위치가 확대를 못 덮는다', () {
    final camera = MapCameraOwner()..moved(byUser: true);

    expect(camera.userMoved, isTrue);
    expect(camera.mayAutoMove, isFalse,
        reason: '을지로까지 확대해 둔 지도가 위치 도착 2초 뒤 성수로 되돌아갔다(실측)');
  });

  test('앱이 옮긴 것은 주인을 안 바꾼다 — 첫 자리잡기 한 번에 영영 잠기면 안 된다', () {
    final camera = MapCameraOwner()..moved(byUser: false);

    expect(camera.mayAutoMove, isTrue);

    // 앱이 여러 번 옮겨도(현위치 → 동네 → 지도 준비) 그대로 앱 차례다.
    camera
      ..moved(byUser: false)
      ..moved(byUser: false);
    expect(camera.mayAutoMove, isTrue);
  });

  test('사용자가 앱에게 옮겨 달라고 하면 다시 앱 차례 — 칩을 눌렀는데 지도가 안 따라오면 다른 고장이다', () {
    final camera = MapCameraOwner()..moved(byUser: true);
    expect(camera.mayAutoMove, isFalse);

    camera.appWasAsked();

    expect(camera.mayAutoMove, isTrue);
    expect(camera.userMoved, isFalse);
  });

  test('부탁한 뒤 또 만지면 다시 사용자 것', () {
    final camera = MapCameraOwner()
      ..moved(byUser: true)
      ..appWasAsked()
      ..moved(byUser: true);

    expect(camera.mayAutoMove, isFalse);
  });
}

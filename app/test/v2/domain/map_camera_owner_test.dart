// 지도 카메라를 누가 쥐고 있나 (#769) — 늦게 온 위치가 사용자의 확대를 덮던 자리의 규칙.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/map_camera_owner.dart';

void main() {
  group('한 번이라도 쥐었나 (mayAutoMove)', () {
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

    test('한 번 쥐면 앱이 그 뒤로 몇 번을 옮겨도 사용자 것이다 — 되돌리는 문이 없다', () {
      // 되돌리는 문(`appWasAsked`)이 있던 때는, 칩을 한 번 누르면 **아직 도착하지 않은**
      // 현위치까지 문이 열려 확대해 둔 지도를 다시 뺏어 갔다(2026-09-21 검토).
      // 부탁은 이제 호출에 실어 보낸다(`_load(byRequest: true)`) — 상태를 안 건드린다.
      final camera = MapCameraOwner()
        ..moved(byUser: true)
        ..moved(byUser: false)
        ..moved(byUser: false);

      expect(camera.mayAutoMove, isFalse,
          reason: '앱이 코스에 맞춰 옮긴 것으로 사용자의 확대가 풀리면 #769 가 되살아난다');
    });
  });

  group('방금 그 이동이 누구 것이었나 (lastMoveByUser)', () {
    test('처음에는 사용자 것이 아니다 — 첫 자리잡기를 "사용자가 왔다" 로 읽지 않는다', () {
      expect(MapCameraOwner().lastMoveByUser, isFalse);
    });

    test('손가락으로 옮기면 참 — 그때만 "이 지역에서 다시 찾기" 를 묻는다', () {
      expect((MapCameraOwner()..moved(byUser: true)).lastMoveByUser, isTrue);
    });

    test('사용자가 끈 뒤 앱이 옮기면 거짓으로 돌아온다 — 끈적이지 않는다', () {
      // 이것이 핵심이다. `mayAutoMove` 는 계속 거짓(사용자 것)이지만, **방금 그 이동**은
      // 앱이 한 것이다. 둘을 하나로 뭉치면 앱이 코스에 맞춰 옮긴 뒤 스스로 다시 조회하고,
      // 그 조회가 방금 그린 코스 선을 지운다(2026-09-21 검토).
      final camera = MapCameraOwner()
        ..moved(byUser: true)
        ..moved(byUser: false);

      expect(camera.lastMoveByUser, isFalse);
      expect(camera.mayAutoMove, isFalse, reason: '쥔 것은 그대로 사용자 것이다');
    });

    test('앱이 옮긴 뒤 다시 손으로 만지면 참', () {
      final camera = MapCameraOwner()
        ..moved(byUser: false)
        ..moved(byUser: true);

      expect(camera.lastMoveByUser, isTrue);
    });
  });
}

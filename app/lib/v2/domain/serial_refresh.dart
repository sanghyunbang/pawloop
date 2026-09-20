// lib/v2/domain/serial_refresh.dart
//
// "한 번에 하나만, 도는 중에 또 부르면 끝난 뒤 한 번 더" — 이슈 #758.
//
// ## 왜 필요한가
//
// 지도의 마커 다시 그리기는 `clearOverlays()` 뒤에 `addOverlayAll()` 을 한다. 부르는 곳이
// 다섯이라(`onMapReady` · 카메라 이동 뒤 `_load` · 검색 · 검색 지우기) 지도 뷰가 처음 뜰 때
// 둘이 **겹친다.** 한쪽이 지우는 동안 다른 쪽이 넣는 중인 마커에 손대면 플러그인이
// "overlay can't found" 를 내고, 그 상태에서 네이버 지도 클러스터러가 AssertionError 로
// 앱을 죽였다(에뮬레이터 실측, 2026-09-21).
//
// 겹친 부름을 **버리지 않는다** — 끝난 뒤 한 번 더 돈다. 그 사이 상태(필터·검색어·중심)가
// 바뀌었을 수 있고, 안 바뀌었으면 같은 그림을 한 번 더 그릴 뿐이다. 세 번 겹쳐도 한 번만
// 더 돈다 — 마지막 상태 하나만 그리면 되기 때문이다.
//
// 토큰 등록(`data/push_registrar.dart`)이 같은 규칙을 안에 들고 있다. 여기는 지도가 쓴다.
library;

class SerialRefresh {
  bool _busy = false;
  bool _again = false;

  /// 지금 도는 중인가.
  bool get isBusy => _busy;

  /// [job] 을 돌린다. 도는 중이면 **바로 돌아오고**, 도는 것이 끝난 뒤 [job] 이 한 번 더 돈다.
  ///
  /// [job] 이 던지면 그 예외는 첫 부름으로 나가고, 다음 부름은 다시 돌 수 있다 — 한 번의
  /// 실패가 지도를 영영 못 그리게 하지 않는다.
  Future<void> run(Future<void> Function() job) async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await job();
      } while (_again);
    } finally {
      _busy = false;
      _again = false;
    }
  }
}

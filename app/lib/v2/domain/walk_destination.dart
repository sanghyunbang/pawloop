// 걸어서 갈 곳 — 이슈 #623.
//
// `WalkPlaceRef`(계약의 `Walk.place`)와 일부러 다른 타입이다. 저쪽은 **기록에 남는
// 꼬리표**라 좌표가 없고, 있을 이유도 없다 — 좌표를 거기 넣으면 산책 하나마다 장소
// 좌표가 서버에 쌓인다. 이쪽은 **추적 화면이 "코스 시작점까지 N km" 를 적을 때 쓰는 좌표**이고
// 기기 밖으로 안 나간다.
//
// 화면이 아니라 여기 있는 이유는 `today_course_card` 가 이 타입을 쓰면서 **화면을
// import 하면 안 되기** 때문이다(`legacy_shell_reachability_test`).
//
// 2026-09-21 까지는 "이 안이면 바로 시작, 밖이면 지도 앱으로 길 안내"(#724)의 기준값(`nearM`)이
// 여기 있었다. 그 결정에 따라 갈림을 지웠다 — 멀어도 우리 추적 화면에서 시작한다. 이 값은
// 이제 **표시**에만 쓴다.
library;

/// 걸어서 갈 곳 — 표시에 필요한 것만. **서버로 안 나간다.**
class WalkDestination {
  final double lat;
  final double lng;

  /// 지금 위치에서 얼마나 먼가. 모르면 `null` — 그러면 거리를 안 적는다.
  final double? distanceM;

  const WalkDestination({required this.lat, required this.lng, this.distanceM});

  /// `450m` · `1.2km`. 카드가 쓰는 규칙과 같게 — 1km 아래는 십의 자리로 끊는다.
  String? get label {
    final d = distanceM;
    if (d == null || d <= 0) return null;
    if (d < 1000) return '${(d / 10).round() * 10}m';
    return '${(d / 100).round() / 10}km';
  }
}

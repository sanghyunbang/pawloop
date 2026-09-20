// 걸어서 갈 곳 — 이슈 #623.
//
// `WalkPlaceRef`(계약의 `Walk.place`)와 일부러 다른 타입이다. 저쪽은 **기록에 남는
// 꼬리표**라 좌표가 없고, 있을 이유도 없다 — 좌표를 거기 넣으면 산책 하나마다 장소
// 좌표가 서버에 쌓인다. 이쪽은 **지도 앱에 건넬 목적지**이고 기기 밖으로 안 나간다.
//
// 화면이 아니라 여기 있는 이유는 `today_course_card` 가 이 타입을 쓰면서 **화면을
// import 하면 안 되기** 때문이다(`legacy_shell_reachability_test`).
library;

/// 걸어서 갈 곳 — 물을 때 필요한 것만. **서버로 안 나간다.**
///
/// `WalkPlaceRef`(계약의 `Walk.place`)와 일부러 다른 타입이다. 저쪽은 **기록에 남는 꼬리표**라
/// 좌표가 없고, 있을 이유도 없다 — 좌표를 거기 넣으면 산책 하나마다 장소 좌표가 서버에
/// 쌓인다. 이쪽은 **지도 앱에 건넬 목적지**이고 기기 밖으로 안 나간다.
class WalkDestination {
  /// 이 안이면 "거기 있다" 로 친다 — 묻지 않고 바로 추적을 시작한다(#724).
  ///
  /// 300m 인 이유: 카탈로그의 점은 공원 한가운데이고 사람은 입구에 서 있다. 큰 공원의 입구와
  /// 중심은 수백 m 다. 여기에 GPS 오차(수십 m)를 더해 한 값으로 뒀다. 근거가 더 생기면
  /// 이 상수 하나만 바꾼다 — 분기는 `startWalk` 한 곳뿐이다.
  static const double nearM = 300;

  final double lat;
  final double lng;

  /// 지금 위치에서 얼마나 먼가. 모르면 `null` — 그러면 거리를 안 적는다.
  final double? distanceM;

  const WalkDestination({required this.lat, required this.lng, this.distanceM});

  /// 기준([nearM]) 안인가. **거리를 모르면 아니다** — 모르는 채로 시작하면 부산 코스가 서울
  /// 산책에 붙는다(#724).
  bool get isNear {
    final d = distanceM;
    return d != null && d <= nearM;
  }

  /// `450m` · `1.2km`. 카드가 쓰는 규칙과 같게 — 1km 아래는 십의 자리로 끊는다.
  String? get label {
    final d = distanceM;
    if (d == null || d <= 0) return null;
    if (d < 1000) return '${(d / 10).round() * 10}m';
    return '${(d / 100).round() / 10}km';
  }
}

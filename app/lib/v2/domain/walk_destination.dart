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
  /// 이 안이면 "걸어서 갈 수 있다" 로 친다 — 묻지 않고 바로 추적을 시작하고, 받은 코스 선을 장소에
  /// 깐 채 그리로 걸어간다(#724 → 2026-09-21).
  ///
  /// 2km 인 이유: 홈 카드가 후보를 고르는 반지름(`CourseCandidates.radiusM` ·
  /// `CourseRecommender.maxDistanceM`)과 같은 값이다 — 카드가 "걸어서 가는 거리" 라며 내민 코스를
  /// 300m 밖이라고 막는 것은 앞뒤가 안 맞았다. 처음 값 300m 는 "공원 한가운데 점과 입구 사이" 를 잰
  /// 것이었는데, 그러면 집에서 카드를 눌러 본 사람은 늘 지도 앱으로 넘어갈 뿐 우리 지도에 그려진 코스를
  /// 볼 수 없었다. 부산 코스를 서울에서 시작하는 일(#724)은 2km 로도 막힌다. 분기는 `startWalk`
  /// 한 곳뿐이고, 셋이 같다는 것은 `start_walk_where_test` 가 잰다.
  static const double nearM = 2000;

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

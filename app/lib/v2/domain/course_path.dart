// 코스의 선 다듬기 — 미리보기용 (#339).
//
// **자르는 것은 서버다.** 여기 있는 것은 저장하기 전에 "이만큼이 빠집니다" 를 보여 주기 위한
// 같은 규칙의 사본이다. 앱이 자른 선을 보내지 않는 이유는 서버 쪽 `CoursePath` 머리말에 있다 —
// 안 자르는 옛 앱 하나가 그 사람의 집 앞을 공개한다.
//
// 그래서 이 파일이 하는 말은 약속이 아니라 **예고**다. 저장 뒤에는 서버가 돌려준 선을 그린다.
import 'dart:math' as math;

/// 양 끝에서 잘라 내는 거리(m). 서버의 `CoursePath.TRIM_METERS` 와 같은 값이다.
const int kCourseTrimMeters = 100;

/// 자르고 남아야 하는 최소 길이(m). 서버의 `MIN_REMAINING_METERS` 와 같다.
const int kCourseMinRemainingMeters = 100;

const double _earthRadiusM = 6371000;

/// 양 끝 [kCourseTrimMeters]m 를 버린 선. 남길 것이 없으면 `null`.
///
/// 점의 개수가 아니라 **거리**로 자른다 — 5m 마다 찍힌 산책과 드문드문 찍힌 산책이 같은
/// 규칙으로 잘려야 한다.
List<List<double>>? trimCourseEnds(List<List<double>>? points) {
  if (points == null || points.length < 2) return null;

  final from = _advance(points, 0, 1);
  final to = _advance(points, points.length - 1, -1);
  if (to - from < 1) return null;

  final trimmed = points.sublist(from, to + 1);
  return coursePathLengthMeters(trimmed) < kCourseMinRemainingMeters ? null : trimmed;
}

/// 선의 길이(m). 점이 하나 이하면 0.
double coursePathLengthMeters(List<List<double>>? points) {
  if (points == null || points.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += _distanceMeters(points[i - 1], points[i]);
  }
  return total;
}

/// 지도의 "이웃 코스" 에 그릴 것들 — **가까운 순 [limit] 개** (#339).
///
/// 서버는 공개 코스 한 벌을 그냥 준다. 어디가 가까운지는 **기기에서** 고른다 — 좌표를 서버로
/// 보내지 않는 A안(#235)이고, 장소 카탈로그(#273)와 같은 방식이다.
///
/// 거리는 **시작점** 기준이다. 선 전체와의 최단거리가 더 정확하지만, 목록 응답에는 시작점만
/// 오고(선은 상세에서 온다) 그 차이가 "가까운 20개" 를 고르는 데 뒤집히는 경우는 드물다.
List<T> nearestByStart<T>(
  List<T> courses,
  double lat,
  double lng, {
  required List<double>? Function(T) startOf,
  int limit = 20,
}) {
  final withDistance = <({T course, double meters})>[];
  for (final course in courses) {
    final start = startOf(course);
    if (start == null || start.length != 2) continue;
    withDistance.add((course: course, meters: _distanceMeters([lng, lat], start)));
  }
  withDistance.sort((a, b) => a.meters.compareTo(b.meters));
  return [for (final row in withDistance.take(limit)) row.course];
}

int _advance(List<List<double>> points, int start, int step) {
  var walked = 0.0;
  var index = start;
  while (true) {
    final next = index + step;
    if (next < 0 || next >= points.length) return index;
    walked += _distanceMeters(points[index], points[next]);
    index = next;
    if (walked >= kCourseTrimMeters) return index;
  }
}

/// 하버사인. `[경도, 위도]` 순서다 — 계약과 같다.
double _distanceMeters(List<double> a, List<double> b) {
  final lat1 = a[1] * math.pi / 180;
  final lat2 = b[1] * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLng = (b[0] - a[0]) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

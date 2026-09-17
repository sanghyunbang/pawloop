// 오늘의 코스 — 규칙으로 고른다 (#485). LLM 없음.
//
// ## 무엇을 하나
//
// 근처 후보(산책로 · 동네 길 · 놀이터 · 공원 · 내 코스)에 오늘의 형편(안전 지수 · 이번 주 목표에서
// 남은 몫 · 최근 간 곳)을 대어 **점수 순으로** 늘어놓는다. 1등이 홈 카드의 "오늘의 코스" 이고
// "다른 코스" 는 그다음이다. 사장님이 2026-09-14 "룰 기반으로" 라고 정했다 — 아카이브 #357 의
// LLM 이유 문장은 위치 신고 뒤다.
//
// ## 이 파일이 모르는 것
//
// 네트워크 · 시계 · 좌표 전송. 후보의 거리는 부르는 쪽이 기기 안에서 잰 값이고(`CourseCandidates`),
// 여기서는 숫자만 비교한다. 그래서 값 테스트로 잰다 — `course_recommender_test`. 소스 잠금은
// `course_recommender_no_network_test` 다.
import 'dart:math' as math;

import '../data/walk_safety.dart' show WalkSafetyLevel;

/// 후보의 종류 — 카드의 아이콘과 점수 보정에 쓴다.
enum CourseKind {
  /// 두루누비 걷기여행길(선이 있다).
  trail('산책로'),

  /// 동네 길(#346) — 시작점만 있다.
  localTrail('동네 길'),

  playground('놀이터'),

  /// 관광공사 "여행지"(공원 · 호수 · 둘레길 입구가 여기 든다).
  park('공원 · 여행지'),

  /// 내가 걸은 길로 만든 코스(#339).
  myCourse('내 코스');

  const CourseKind(this.label);
  final String label;
}

/// 후보 하나. [distanceM] 은 지금 위치에서 시작점까지, [lengthM] 은 코스 길이(모르면 null —
/// 점 하나짜리 장소는 길이가 없다. "왕복 N km" 를 지어내지 않는다).
class CourseCandidate {
  final String id;
  final String title;
  final CourseKind kind;
  final double distanceM;
  final double? lengthM;
  final String? image;

  /// `startWalk(place:)` 에 넘길 재료 — 카탈로그 장소만 있다. 내 코스는 이름만.
  final String? source;
  final String? contentId;

  /// 그 코스가 **어디인가** (#623). "어디서 시작할까요?" 가 지도 앱에 건넬 목적지다.
  ///
  /// 카탈로그 장소는 그 점이고, 내 코스는 시작 지점이다. 둘 다 있을 수 있는 값이라
  /// 선택으로 뒀지만, 없으면 **묻지 못하고 예전처럼 그 자리에서 시작**한다.
  final double? lat;
  final double? lng;

  const CourseCandidate({
    required this.id,
    required this.title,
    required this.kind,
    required this.distanceM,
    this.lengthM,
    this.image,
    this.source,
    this.contentId,
    this.lat,
    this.lng,
  });

  bool get isMine => kind == CourseKind.myCourse;
}

/// 점수가 매겨진 후보 하나. [score] 는 낮을수록 좋다.
class CourseRecommendation {
  final CourseCandidate course;
  final double score;

  /// 오늘 걸을 만한 길이(km) — 이유 문장의 "목표 N km".
  final double targetKm;

  /// 최근 7일에 간 곳이라 뒤로 밀렸다.
  final bool visitedRecently;

  /// 안전 지수 때문에 목표를 반으로 줄였다.
  final bool shortened;

  const CourseRecommendation({
    required this.course,
    required this.score,
    required this.targetKm,
    required this.visitedRecently,
    required this.shortened,
  });
}

class CourseRecommender {
  /// 내 기록이 셋 미만이면 이 속도로 잰다 — 반려견과 걷는 보통 속도.
  static const double defaultPaceKmPerHour = 4;

  /// 아무리 줄여도 이보다 짧은 목표는 안 낸다 — 0.8km 아래는 "산책" 이 아니다.
  static const double minTargetKm = 0.8;

  /// 후보 반경. 걸어서 가는 거리라 2km 다.
  static const double maxDistanceM = 2000;

  /// 점수 순 목록. 안전 지수가 [WalkSafetyLevel.avoid] 면 **빈 목록** — 카드는 "오늘은 쉬어요".
  ///
  /// [targetMinutes] 는 오늘 걸을 분([todayMinutes]), [recentIds] 는 최근 7일에 간 후보 id,
  /// [hot] 은 25°C 이상 — 그때는 공원 · 산책로(물가 · 나무)가 놀이터보다 앞선다.
  static List<CourseRecommendation> rank({
    required List<CourseCandidate> candidates,
    required int targetMinutes,
    WalkSafetyLevel? safety,
    double paceKmPerHour = defaultPaceKmPerHour,
    Set<String> recentIds = const {},
    bool hot = false,
  }) {
    if (safety == WalkSafetyLevel.avoid) return const [];
    final shortened = safety == WalkSafetyLevel.short || safety == WalkSafetyLevel.cold;
    var targetKm = targetMinutes / 60 * paceKmPerHour;
    if (shortened) targetKm /= 2;
    if (targetKm < minTargetKm) targetKm = minTargetKm;

    final scored = <CourseRecommendation>[];
    for (final c in candidates) {
      if (c.distanceM > maxDistanceM) continue;
      var score = 0.0;
      // 길이 차이(km) — 모르면 0.5 만큼 불리하게. 아는 후보를 먼저 세우되 모르는 것도 나온다.
      final length = c.lengthM;
      score += length == null ? 0.5 : (length / 1000 - targetKm).abs();
      // 가까울수록 — 1km 에 0.5.
      score += c.distanceM / 1000 * 0.5;
      final recent = recentIds.contains(c.id);
      if (recent) score += 2;
      if (c.isMine) score -= 0.5;
      if (hot && (c.kind == CourseKind.park || c.kind == CourseKind.trail)) score -= 0.3;
      scored.add(CourseRecommendation(
        course: c,
        score: score,
        targetKm: targetKm,
        visitedRecently: recent,
        shortened: shortened,
      ));
    }
    scored.sort((a, b) {
      final s = a.score.compareTo(b.score);
      return s != 0 ? s : a.course.distanceM.compareTo(b.course.distanceM);
    });
    return scored;
  }

  /// 오늘 걸을 분 — 하루 권장과 이번 주에 남은 몫 중 작은 것. 목표를 다 채웠으면 가볍게(권장의 반),
  /// 어느 경우든 15분 아래로는 안 내린다.
  static int todayMinutes({
    required int dailyMinutes,
    required int weeklyMinutes,
    required int minutesThisWeek,
  }) {
    final remaining = weeklyMinutes - minutesThisWeek;
    if (remaining <= 0) return math.max(15, dailyMinutes ~/ 2);
    return math.max(15, math.min(dailyMinutes, remaining));
  }

  /// 내 기록의 평균 속도(km/h). 기록이 셋 미만이거나 이상한 값(0 초 · 시속 12km 이상)이면 기본값.
  static double paceOf(Iterable<({int distanceM, int durationS})> walks) {
    var meters = 0, seconds = 0, n = 0;
    for (final w in walks) {
      if (w.durationS <= 0 || w.distanceM <= 0) continue;
      meters += w.distanceM;
      seconds += w.durationS;
      n++;
    }
    if (n < 3 || seconds == 0) return defaultPaceKmPerHour;
    final pace = meters / 1000 / (seconds / 3600);
    return pace <= 0 || pace >= 12 ? defaultPaceKmPerHour : pace;
  }
}

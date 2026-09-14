// 오늘의 코스 추천기 — 값으로 잰다 (#485). 순수 함수라 화면 없이.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_safety.dart';
import 'package:heat_trip_flutter/v2/domain/course_recommender.dart';

const _trail = CourseCandidate(
    id: 'trail:1', title: '서울숲 둘레길', kind: CourseKind.trail, distanceM: 500, lengthM: 3000, source: 'trail', contentId: 'trail:1');
const _park = CourseCandidate(
    id: '2733847', title: '서울숲 호수', kind: CourseKind.park, distanceM: 800, lengthM: 1200, source: 'kto', contentId: '2733847');
const _local = CourseCandidate(
    id: 'trail:lt9', title: '뚝섬 동네 길', kind: CourseKind.localTrail, distanceM: 300, lengthM: 2400, source: 'trail', contentId: 'trail:lt9');
const _playground = CourseCandidate(
    id: 'pg:1', title: '성수 놀이터', kind: CourseKind.playground, distanceM: 200, source: 'playground', contentId: 'pg:1');
const _mine = CourseCandidate(id: 'course:7', title: '아침 한 바퀴', kind: CourseKind.myCourse, distanceM: 1500, lengthM: 2000);
const _far = CourseCandidate(id: 'trail:far', title: '한강 먼 길', kind: CourseKind.trail, distanceM: 5000, lengthM: 2000);

const _five = [_trail, _park, _local, _playground, _mine];

List<String> _order(List<CourseRecommendation> r) => [for (final x in r) x.course.id];

void main() {
  group('rank', () {
    test('보통 날 · 목표 30분(2km)이면 길이가 2km 에 가까운 것이 앞이고, 2km 밖 후보는 빠진다', () {
      final r = CourseRecommender.rank(candidates: [..._five, _far], targetMinutes: 30);
      expect(_order(r).first, 'course:7', reason: '내 코스 2.0km, 가점 0.5');
      expect(_order(r), isNot(contains('trail:far')));
      expect(r.first.targetKm, closeTo(2.0, 0.001));
      expect(r.first.shortened, isFalse);
    });

    test('더움 + 짧게(short) 면 목표가 반이 되고 공원 · 산책로가 앞선다 — 시니어 · 단두종의 여름', () {
      final r = CourseRecommender.rank(
          candidates: _five, targetMinutes: 30, safety: WalkSafetyLevel.short, hot: true);
      expect(r.first.targetKm, closeTo(1.0, 0.001));
      expect(r.first.shortened, isTrue);
      expect(_order(r).first, '2733847', reason: '1.2km 공원이 1km 목표에 가장 가깝고 더위 가점');
    });

    test('피하세요(avoid)면 빈 목록 — 카드는 "오늘은 쉬어요" 로 간다', () {
      expect(CourseRecommender.rank(candidates: _five, targetMinutes: 30, safety: WalkSafetyLevel.avoid), isEmpty);
    });

    test('추위(cold)도 짧게 — 목표가 반이다', () {
      final r = CourseRecommender.rank(candidates: _five, targetMinutes: 60, safety: WalkSafetyLevel.cold);
      expect(r.first.targetKm, closeTo(2.0, 0.001));
      expect(r.first.shortened, isTrue);
    });

    test('지난 7일에 간 곳은 뒤로 밀린다 — 같은 곳을 연속으로 권하지 않는다', () {
      final before = CourseRecommender.rank(candidates: _five, targetMinutes: 30);
      final after = CourseRecommender.rank(candidates: _five, targetMinutes: 30, recentIds: {'course:7'});
      expect(_order(before).first, 'course:7');
      expect(_order(after).first, isNot('course:7'));
      expect(after.singleWhere((x) => x.course.id == 'course:7').visitedRecently, isTrue);
    });

    test('길이를 모르는 후보(놀이터)는 지어내지 않고 조금 뒤에 선다 — 그래도 목록에는 있다', () {
      // 목표 1.2km(18분) — 공원은 차이 0 + 거리 0.4, 놀이터는 모름 0.5 + 거리 0.1.
      final r = CourseRecommender.rank(candidates: [_playground, _park], targetMinutes: 18);
      expect(_order(r), ['2733847', 'pg:1']);
      expect(r.last.course.lengthM, isNull);
    });

    test('목표가 아무리 짧아도 0.8km 아래로는 안 내린다', () {
      final r = CourseRecommender.rank(candidates: _five, targetMinutes: 15, safety: WalkSafetyLevel.short);
      expect(r.first.targetKm, closeTo(0.8, 0.001));
    });

    test('점수가 같으면 가까운 것이 먼저다', () {
      const a = CourseCandidate(id: 'a', title: 'a', kind: CourseKind.park, distanceM: 400, lengthM: 2000);
      const b = CourseCandidate(id: 'b', title: 'b', kind: CourseKind.park, distanceM: 400, lengthM: 2000);
      final r = CourseRecommender.rank(candidates: const [b, a], targetMinutes: 30);
      expect(r.first.score, r.last.score);
      expect(_order(r), ['b', 'a'], reason: '같으면 들어온 순서 — 정렬이 안정적이다');
    });
  });

  group('todayMinutes', () {
    test('이번 주에 남은 몫과 하루 권장 중 작은 것', () {
      expect(CourseRecommender.todayMinutes(dailyMinutes: 30, weeklyMinutes: 150, minutesThisWeek: 130), 20);
      expect(CourseRecommender.todayMinutes(dailyMinutes: 30, weeklyMinutes: 150, minutesThisWeek: 0), 30);
    });
    test('목표를 다 채웠으면 가볍게(권장의 반), 15분 아래로는 안 내린다', () {
      expect(CourseRecommender.todayMinutes(dailyMinutes: 30, weeklyMinutes: 150, minutesThisWeek: 150), 15);
      expect(CourseRecommender.todayMinutes(dailyMinutes: 60, weeklyMinutes: 300, minutesThisWeek: 320), 30);
      expect(CourseRecommender.todayMinutes(dailyMinutes: 20, weeklyMinutes: 100, minutesThisWeek: 95), 15);
    });
  });

  group('paceOf', () {
    test('기록이 셋 미만이면 4km/h', () {
      expect(CourseRecommender.paceOf([(distanceM: 1000, durationS: 600)]), 4);
    });
    test('셋 이상이면 평균 — 1.2km 를 20분씩 셋이면 3.6km/h', () {
      final walks = List.generate(3, (_) => (distanceM: 1200, durationS: 1200));
      expect(CourseRecommender.paceOf(walks), closeTo(3.6, 0.001));
    });
    test('이상한 값(0초 · 시속 12km 이상)은 세지 않거나 기본값으로', () {
      expect(CourseRecommender.paceOf([(distanceM: 1000, durationS: 0), (distanceM: 1000, durationS: 0), (distanceM: 1000, durationS: 0)]), 4);
      final sprint = List.generate(3, (_) => (distanceM: 5000, durationS: 600));
      expect(CourseRecommender.paceOf(sprint), 4, reason: '시속 30km 는 산책이 아니다');
    });
  });
}

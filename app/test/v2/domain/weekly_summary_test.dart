// 이번 주 요약 — 이슈 #359 1단계.
//
// ## 여기서 재는 가장 중요한 것
//
// **모르는 것은 안 적는가.** 예전 요약은 사용자가 옆 막대에서 이미 읽은 숫자를 문장으로
// 다시 적었고, 그전에는 "주말에 가장 활발했고 서울숲 평지 코스를 추천해요" 같은 근거 없는
// 주장을 했다(#332 가 지웠다).
//
// 그래서 여기서는 **줄이 없는 경우**를 줄이 있는 경우만큼 잰다 — 목표가 없으면 달성률이
// 없고, 지난주 기록이 없으면 비교가 없고, 빠진 요일이 없으면 제안이 없다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/walk_goal.dart';
import 'package:heat_trip_flutter/v2/domain/weekly_summary.dart';

/// 화·목·토 저녁 세 번을 걸은 주. 이슈 본문의 예다.
WeeklySummary _tueThuSatEvening({
  WalkGoal? goal,
  WeekSummaryData summary = WeekSummaryData.empty,
}) =>
    WeeklySummary.of(
      walkCount: 3,
      totalKm: 6.0,
      weekKm: const [0, 2, 0, 2, 0, 2, 0],
      weekMinutes: const [0, 30, 0, 30, 0, 30, 0],
      summary: summary,
      goal: goal,
    );

WeekSummaryData _summary({
  double lastWeekKm = 0,
  int lastWeekMinutes = 0,
  int lastWeekCount = 0,
  int dawn = 0,
  int morning = 0,
  int afternoon = 0,
  int evening = 0,
}) =>
    WeekSummaryData(
      lastWeekKm: lastWeekKm,
      lastWeekMinutes: lastWeekMinutes,
      lastWeekCount: lastWeekCount,
      byPartOfDay: [
        PartOfDayCount(part: 'dawn', count: dawn, km: 0, minutes: 0),
        PartOfDayCount(part: 'morning', count: morning, km: 0, minutes: 0),
        PartOfDayCount(part: 'afternoon', count: afternoon, km: 0, minutes: 0),
        PartOfDayCount(part: 'evening', count: evening, km: 0, minutes: 0),
      ],
    );

void main() {
  group('기록이 없을 때', () {
    test('숫자를 지어내지 않고 한 줄만 말한다', () {
      final s = WeeklySummary.of(
        walkCount: 0,
        totalKm: 0,
        weekKm: const [0, 0, 0, 0, 0, 0, 0],
        weekMinutes: const [0, 0, 0, 0, 0, 0, 0],
        summary: WeekSummaryData.empty,
        goal: const WalkGoal(daysPerWeek: 5, minutesPerWeek: 150),
      );

      expect(s.lines, isEmpty);
      expect(s.suggestion, isNull, reason: '한 번도 안 걸은 사람에게 "한 번 더" 는 할 말이 아니다');
      expect(s.text, WeeklySummary.emptyLine);
    });
  });

  group('사실 문장', () {
    test('횟수 · 거리 · 분을 먼저 말한다', () {
      expect(_tueThuSatEvening().lines.first, '이번 주 3회 · 6.0km · 90분 걸었어요.');
    });

    test('목표가 있으면 달성률을 적는다 — 완료 조건 2', () {
      final s = _tueThuSatEvening(goal: const WalkGoal(daysPerWeek: 5, minutesPerWeek: 150));

      expect(s.text, contains('목표는 주 5일 · 150분인데 3일 · 90분, 60% 예요.'));
    });

    test('목표가 없으면 달성률 줄이 아예 없다 — 개가 아닌 아이에게는 권장량 자료가 없다', () {
      final s = _tueThuSatEvening();

      expect(s.text, isNot(contains('목표')));
      expect(s.text, isNot(contains('%')));
    });

    test('빠진 요일을 적는다', () {
      // 월·수·금·일 넷이 빠졌으므로 나열하지 않는다 — 이름 넷은 문장이 아니라 목록이다.
      expect(_tueThuSatEvening().text, isNot(contains('요일엔 못 나갔어요')));

      final threeMissing = WeeklySummary.of(
        walkCount: 4,
        totalKm: 8.0,
        weekKm: const [2, 0, 2, 0, 2, 2, 0],
        weekMinutes: const [30, 0, 30, 0, 30, 30, 0],
        summary: WeekSummaryData.empty,
      );
      expect(threeMissing.text, contains('화·목·일요일엔 못 나갔어요.'));
    });

    test('다 걸은 주에는 빠짐을 화제로 올리지 않는다', () {
      final everyDay = WeeklySummary.of(
        walkCount: 7,
        totalKm: 14.0,
        weekKm: const [2, 2, 2, 2, 2, 2, 2],
        weekMinutes: const [30, 30, 30, 30, 30, 30, 30],
        summary: _summary(evening: 7),
      );

      expect(everyDay.text, isNot(contains('못 나갔어요')));
      expect(everyDay.suggestion, isNull, reason: '매일 걸은 사람에게 "한 번 더" 는 할 말이 아니다');
    });
  });

  group('지난주 대비', () {
    test('늘었으면 늘었다고 적는다', () {
      final s = _tueThuSatEvening(summary: _summary(lastWeekKm: 4.0, lastWeekCount: 2));

      expect(s.text, contains('지난주보다 2.0km 더 걸었어요.'));
    });

    test('줄었으면 줄었다고 적는다 — 좋게 돌려 말하지 않는다', () {
      final s = _tueThuSatEvening(summary: _summary(lastWeekKm: 9.0, lastWeekCount: 3));

      expect(s.text, contains('지난주보다 3.0km 적게 걸었어요.'));
    });

    test('거의 같으면 "비슷해요" 다 — 0.0km 차이를 숫자로 적지 않는다', () {
      final s = _tueThuSatEvening(summary: _summary(lastWeekKm: 6.02, lastWeekCount: 3));

      expect(s.text, contains('지난주와 비슷해요.'));
      expect(s.text, isNot(contains('0.0km')));
    });

    test('지난주 기록이 없으면 비교하지 않는다 — 앱을 안 쓴 주와 견주면 뜻이 없다', () {
      final s = _tueThuSatEvening(summary: _summary(lastWeekCount: 0, evening: 3));

      expect(s.text, isNot(contains('지난주')));
    });
  });

  group('제안', () {
    test('빠진 요일과 자주 가는 시간대로 만든다', () {
      final s = WeeklySummary.of(
        walkCount: 4,
        totalKm: 8.0,
        weekKm: const [2, 0, 2, 0, 2, 2, 0],
        weekMinutes: const [30, 0, 30, 0, 30, 30, 0],
        summary: _summary(evening: 3, morning: 1),
      );

      expect(s.suggestion, '다음 주엔 화요일 저녁에 한 번 더 어때요.');
    });

    test('시간대를 모르면 제안하지 않는다 — 아무 때나 찍어 말하지 않는다', () {
      final s = WeeklySummary.of(
        walkCount: 4,
        totalKm: 8.0,
        weekKm: const [2, 0, 2, 0, 2, 2, 0],
        weekMinutes: const [30, 0, 30, 0, 30, 30, 0],
        summary: WeekSummaryData.empty,
      );

      expect(s.suggestion, isNull);
    });

    test('같은 횟수면 이른 시간대를 고른다 — 순위를 지어내지 않는다', () {
      final data = _summary(morning: 2, evening: 2);

      expect(data.busiestPart?.part, 'morning');
    });
  });

  group('서버 응답 읽기', () {
    test('summary 가 없으면 빈 값이다 — null 을 위로 흘리지 않는다', () {
      expect(WeekSummaryData.parse(null).byPartOfDay, isEmpty);
      expect(WeekSummaryData.parse('이상한 값').lastWeekCount, 0);
    });

    test('모르는 시간대 이름은 라벨이 없다 — 지어내지 않는다', () {
      final parsed = WeekSummaryData.parse({
        'lastWeekKm': 1.5,
        'lastWeekMinutes': 20,
        'lastWeekCount': 1,
        'byPartOfDay': [
          {'part': 'evening', 'count': 2, 'km': 4.0, 'minutes': 60},
          {'part': 'midnight', 'count': 9, 'km': 1.0, 'minutes': 10},
        ],
      });

      expect(parsed.lastWeekKm, 1.5);
      expect(parsed.byPartOfDay.first.label, '저녁');
      expect(parsed.byPartOfDay.last.label, isNull);
      expect(parsed.busiestPart?.part, 'midnight',
          reason: '라벨은 없어도 집계는 맞다 — 제안 문장에서만 걸러진다');
    });
  });
}

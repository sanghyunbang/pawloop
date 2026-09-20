// 주간 산책 목표와 연속 일수 — 이슈 #341.
//
// ## 여기서 재는 것
//
//  1. **제안 표가 코드와 문서에서 같은가.** 완료 조건 1 이다 — 문서에 30분이라고 적고
//     코드가 20분을 제안하면, 그 화면의 "참고" 라벨이 가리키는 근거가 거짓이 된다.
//  2. **연속 일수가 오늘 안 걸은 저녁에 0 이 되지 않는가.** 저녁 7시에 홈을 연 사람에게
//     "0일" 을 보여 주면 아직 나갈 수 있는데 이미 끊겼다고 말하는 셈이다.
//  3. **링이 낙관적이지 않은가.** 날과 분 중 덜 찬 쪽으로 채운다 — 일요일에 몰아 걷기가
//     "다 했다" 로 보이면 목표가 뜻을 잃는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/domain/walk_goal.dart';

DateTime _d(int day) => DateTime(2026, 9, day);

void main() {
  group('제안값 — 크기와 나이로', () {
    test('성견은 크기로 하루 30·45·60분', () {
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.small, ageMonths: 0), 30);
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.medium, ageMonths: 0), 45);
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.large, ageMonths: 0), 60);
    });

    test('나이를 아는 강아지는 월령 × 5분을 하루 두 번', () {
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.small, ageMonths: 4), 40);
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.large, ageMonths: 6), 60);
    });

    test('열두 달부터는 성견 표로 돌아간다', () {
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.small, ageMonths: 12), 30);
    });

    test('나이를 모르면(0) 성견 기준이다 — 모르는 상태에서 적게 권하는 쪽이 더 나쁘다', () {
      // 지금 앱의 등록 시트가 생일을 안 받아 대부분 0 이다(DogProfile.ageLabel 주석).
      expect(WalkGoal.recommendedDailyMinutes(size: DogSize.medium, ageMonths: 0), 45);
    });

    test('주 목표는 하루 권장 × 5일이다 — 매일을 목표로 걸면 하루만 빠져도 실패가 된다', () {
      final goal = WalkGoal.recommendedFor(
        species: PetSpecies.dog,
        size: DogSize.medium,
        ageMonths: 0,
      );

      expect(goal, const WalkGoal(daysPerWeek: 5, minutesPerWeek: 225));
    });

    test('개가 아니면 제안하지 않는다 — 산책 권장량은 개에 대한 자료다', () {
      expect(
        WalkGoal.recommendedFor(
            species: PetSpecies.cat, size: DogSize.small, ageMonths: 0),
        isNull,
      );
      expect(
        WalkGoal.recommendedFor(
            species: PetSpecies.other, size: DogSize.small, ageMonths: 0),
        isNull,
      );
    });
  });

  group('문서와 코드가 같은 숫자를 말한다 (완료 조건 1)', () {
    late String spec;

    setUpAll(() {
      final file = File('../docs/01-design/feature-spec.md');
      if (!file.existsSync()) {
        throw StateError('${file.path} 가 없다 — 경로가 바뀌었으면 이 테스트도 함께 고친다');
      }
      spec = file.readAsStringSync();
    });

    test('성견 세 줄이 문서에 그대로 있다', () {
      for (final entry in {
        DogSize.small: 30,
        DogSize.medium: 45,
        DogSize.large: 60,
      }.entries) {
        final minutes = WalkGoal.recommendedDailyMinutes(size: entry.key, ageMonths: 0);
        expect(minutes, entry.value);
        expect(spec, contains('${entry.key.labelFor(PetSpecies.dog)} 하루 $minutes분'),
            reason: '문서와 코드가 갈리면 화면의 "참고" 라벨이 가리키는 근거가 거짓이 된다');
      }
    });

    test('강아지 규칙과 "참고" 라벨이 문서에 있다', () {
      expect(spec, contains('월령 × 5분'));
      expect(spec, contains('참고'),
          reason: '수의사의 지시가 아니라는 말이 화면과 문서에 함께 있어야 한다');
    });
  });

  group('이번 주 진행', () {
    const goal = WalkGoal(daysPerWeek: 5, minutesPerWeek: 90);

    test('덜 찬 쪽으로 채운다 — 몰아 걷기가 "다 했다" 로 보이면 안 된다', () {
      // 하루에 90분을 몰아 걸었다: 분은 100%, 날은 20%.
      const progress = WalkGoalProgress(goal: goal, days: 1, minutes: 90);

      expect(progress.ratio, closeTo(0.2, 0.001));
      expect(progress.met, isFalse);
    });

    test('둘 다 채워야 달성이다', () {
      const progress = WalkGoalProgress(goal: goal, days: 5, minutes: 90);

      expect(progress.met, isTrue);
      expect(progress.ratio, 1.0);
    });

    test('넘겨도 1.0 을 안 넘는다 — 막대가 칸 밖으로 나가면 안 된다', () {
      const progress = WalkGoalProgress(goal: goal, days: 7, minutes: 300);

      expect(progress.ratio, 1.0);
    });

    test('문장은 "3/5일 · 42/90분" 이다', () {
      const progress = WalkGoalProgress(goal: goal, days: 3, minutes: 42);

      expect(progress.label, '3/5일 · 42/90분');
    });
  });

  group('연속 일수 — 혼내지 않는다', () {
    test('오늘까지 이어져 있으면 오늘을 포함해 센다', () {
      expect(walkStreakDays([_d(5), _d(6), _d(7)], today: _d(7)), 3);
    });

    test('오늘 아직 안 걸었어도 어제까지의 연속은 살아 있다', () {
      expect(
        walkStreakDays([_d(4), _d(5), _d(6)], today: _d(7)),
        3,
        reason: '저녁 7시에 0일을 보여 주면 아직 나갈 수 있는 사람에게 끊겼다고 말하는 셈이다',
      );
    });

    test('어제도 그제도 없으면 0 이다', () {
      expect(walkStreakDays([_d(3)], today: _d(7)), 0);
    });

    test('하루에 두 번 걸어도 하루로 센다', () {
      expect(
        walkStreakDays([
          DateTime(2026, 9, 7, 8),
          DateTime(2026, 9, 7, 20),
        ], today: _d(7)),
        1,
      );
    });

    test('기록이 없으면 0 이다', () {
      expect(walkStreakDays(const [], today: _d(7)), 0);
    });
  });

  group('저장 형식', () {
    test('적은 대로 읽힌다', () {
      const goal = WalkGoal(daysPerWeek: 4, minutesPerWeek: 120);

      expect(WalkGoal.tryParse(goal.toJson()), goal);
    });

    test('말이 안 되는 값은 null — 0일짜리 목표는 나눗셈을 0 으로 만든다', () {
      expect(WalkGoal.tryParse({'daysPerWeek': 0, 'minutesPerWeek': 100}), isNull);
      expect(WalkGoal.tryParse({'daysPerWeek': 8, 'minutesPerWeek': 100}), isNull);
      expect(WalkGoal.tryParse({'daysPerWeek': 3, 'minutesPerWeek': 0}), isNull);
      expect(WalkGoal.tryParse('주 5일'), isNull);
    });
  });
}

// lib/v2/domain/walk_goal.dart
//
// 우리 아이 기준의 주간 산책 목표 — 이슈 #341.
//
// ## 왜 목표가 필요한가
//
// 앱은 지금 기록을 받기만 하고 **먼저 말을 걸지 않는다.** 페르소나 P3(바쁜 직장인)의 첫
// 불편이 "바빠서 건너뛰고, 기억이 안 나 '오늘 나갔었나' 헷갈린다" 인데, 화면에 그것을
// 되돌려 주는 자리가 통계의 막대 하나뿐이다.
//
// ## 왜 포인트가 아닌가
//
// 경쟁 앱(펫피)은 포인트로 루틴을 만든다 — 1분에 2포인트, 하루 30분에 보너스. 그건 사람을
// 움직이지만 **아이에게 맞는 양과 무관하다.** 소형견에게 하루 두 시간은 목표가 아니라 무리다.
// 그래서 여기서는 크기·나이로 권장량을 제안하고, 그 숫자가 어디서 왔는지 화면에 적는다.
//
// ## 숫자의 출처
//
// 아래 표는 PDSA·Kennel Club·Dogster 의 일반 권장량이다. **수의사의 지시가 아니다** —
// 화면이 그 말을 "참고" 라벨로 함께 적고, 사용자가 언제든 고칠 수 있다. 우리는 아이의
// 건강 상태를 모른다.
//
//   · 강아지(12개월 미만) — 월령 × 5분, 하루 두 번까지 (Kennel Club 의 오래된 규칙)
//   · 성견 소형 — 하루 30분   (저에너지 소형견은 20~30분)
//   · 성견 중형 — 하루 45분   (일반 성견 30분~2시간의 아래쪽)
//   · 성견 대형 — 하루 60분   (사역·스포팅 견종은 60~120분)
//
// ## 왜 하루가 아니라 주 단위인가
//
// 하루 목표는 못 지킨 날마다 실패를 만든다. 바쁜 사람이 화요일을 건너뛰고 토요일에 두 배로
// 걷는 것은 실패가 아니다. 그래서 **주 5일 · 주 몇 분**으로 잡는다 — 이슈의 "이번 주 3/5일
// 42/90분" 이 그 모양이다.
library;

import 'pet.dart';

/// 한 주의 목표. 날 수와 분을 함께 든다 — 둘 중 하나만으로는 부족하다.
///
/// 날 수만 세면 5분씩 다섯 번 나간 주가 목표 달성이 되고, 분만 세면 일요일에 몰아서
/// 90분을 걸은 주가 "매일 걸었다" 와 같아진다.
class WalkGoal {
  const WalkGoal({required this.daysPerWeek, required this.minutesPerWeek});

  /// 주 며칠. 1~7.
  final int daysPerWeek;

  /// 주 몇 분.
  final int minutesPerWeek;

  /// 제안값의 기본 날 수. **7 이 아니다** — 매일을 목표로 걸면 하루만 빠져도 실패가 된다.
  static const int defaultDaysPerWeek = 5;

  /// 크기·나이로 제안한다. **강아지(고양이·기타)에게는 제안하지 않는다.**
  ///
  /// 산책 권장량은 개에 대한 자료다. 고양이에게 "주 5일 150분" 을 제안하면 그건 근거 없는
  /// 숫자이고, 화면은 그 카드를 아예 안 그린다.
  ///
  /// [ageMonths] 가 0 이면 **나이를 모르는 것이다** — 지금 앱의 등록 시트가 생일을 안 받아서
  /// 대부분 0 이다(`DogProfile.ageLabel` 의 주석). 그때는 성견 기준으로 제안한다. 강아지에게
  /// 성견 기준을 권하면 많고, 성견에게 강아지 기준을 권하면 적은데, **모르는 상태에서
  /// 적게 권하는 쪽이 더 나쁘다** — 성견의 부족한 운동은 문제 행동으로 돌아온다.
  static WalkGoal? recommendedFor({
    required PetSpecies species,
    required DogSize size,
    required int ageMonths,
  }) {
    if (species != PetSpecies.dog) return null;
    final perDay = recommendedDailyMinutes(size: size, ageMonths: ageMonths);
    return WalkGoal(
      daysPerWeek: defaultDaysPerWeek,
      minutesPerWeek: perDay * defaultDaysPerWeek,
    );
  }

  /// 하루 권장 분. 위 표 그대로다.
  static int recommendedDailyMinutes({required DogSize size, required int ageMonths}) {
    // 나이를 아는 강아지 — 월령 × 5분을 하루 두 번까지.
    if (ageMonths > 0 && ageMonths < 12) {
      return ageMonths * 5 * 2;
    }
    return switch (size) {
      DogSize.small => 30,
      DogSize.medium => 45,
      DogSize.large => 60,
    };
  }

  /// 화면이 함께 적는 한 줄. **"참고" 라는 말이 여기 들어 있다.**
  static String get sourceLabel => '참고 · 크기와 나이로 제안한 값이에요 · 언제든 고칠 수 있어요';

  Map<String, dynamic> toJson() => {
        'daysPerWeek': daysPerWeek,
        'minutesPerWeek': minutesPerWeek,
      };

  /// 모양이 다르면 `null`. 저장 형식이 바뀌어도 홈이 죽지 않아야 한다.
  static WalkGoal? tryParse(Object? json) {
    if (json is! Map) return null;
    final days = (json['daysPerWeek'] as num?)?.toInt();
    final minutes = (json['minutesPerWeek'] as num?)?.toInt();
    if (days == null || minutes == null) return null;
    if (days < 1 || days > 7 || minutes < 1) return null;
    return WalkGoal(daysPerWeek: days, minutesPerWeek: minutes);
  }

  @override
  bool operator ==(Object other) =>
      other is WalkGoal &&
      other.daysPerWeek == daysPerWeek &&
      other.minutesPerWeek == minutesPerWeek;

  @override
  int get hashCode => Object.hash(daysPerWeek, minutesPerWeek);

  @override
  String toString() => 'WalkGoal($daysPerWeek일 · $minutesPerWeek분)';
}

/// 이번 주가 목표에 얼마나 왔나. 화면이 링과 문장을 이것으로 그린다.
class WalkGoalProgress {
  const WalkGoalProgress({
    required this.goal,
    required this.days,
    required this.minutes,
  });

  final WalkGoal goal;

  /// 이번 주에 **산책한 날 수**. 하루에 두 번 걸어도 1 이다.
  final int days;

  /// 이번 주에 걸은 분.
  final int minutes;

  /// 0.0~1.0. **날과 분 중 덜 찬 쪽**을 쓴다 — 링 하나가 두 숫자를 대표하려면
  /// 낙관적인 쪽을 보여 주면 안 된다. 몰아 걷기가 "다 했다" 로 보이면 목표가 뜻을 잃는다.
  double get ratio {
    final byDays = goal.daysPerWeek == 0 ? 0.0 : days / goal.daysPerWeek;
    final byMinutes = goal.minutesPerWeek == 0 ? 0.0 : minutes / goal.minutesPerWeek;
    final smaller = byDays < byMinutes ? byDays : byMinutes;
    return smaller.clamp(0.0, 1.0);
  }

  bool get met => days >= goal.daysPerWeek && minutes >= goal.minutesPerWeek;

  /// "3/5일 · 42/90분".
  String get label => '$days/${goal.daysPerWeek}일 · $minutes/${goal.minutesPerWeek}분';
}

/// 오늘까지 며칠 연속으로 걸었나 — 이슈 #341.
///
/// **오늘 아직 안 걸었어도 어제까지의 연속은 살아 있다.** 저녁 7시에 홈을 열었을 때
/// "0일" 을 보여 주면, 아직 나갈 수 있는 사람에게 이미 끊겼다고 말하는 셈이다.
/// 그래서 오늘 기록이 없으면 **어제부터** 센다.
///
/// [dates] 는 산책이 있었던 날들이다(중복·순서 무관, 시각은 무시한다).
int walkStreakDays(Iterable<DateTime> dates, {required DateTime today}) {
  final days = <DateTime>{
    for (final d in dates) DateTime(d.year, d.month, d.day),
  };
  if (days.isEmpty) return 0;

  final start = DateTime(today.year, today.month, today.day);
  // 오늘 걸었으면 오늘부터, 아니면 어제부터 — 어제도 없으면 0 이다.
  var cursor = days.contains(start) ? start : start.subtract(const Duration(days: 1));
  if (!days.contains(cursor)) return 0;

  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

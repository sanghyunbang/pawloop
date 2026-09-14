// lib/v2/domain/weekly_summary.dart
//
// "이번 주 요약" — 이슈 #359 1단계.
//
// ## 왜 있나
//
// 통계 화면의 요약은 문자열 조립이었다 — "이번 주는 3회 · 6.2km 걸었어요. 화요일에 가장
// 많이 걸었고, 평균 2.1km 예요." 사실이지만 **아무것도 말해 주지 않는다.** 사용자가 이미
// 화면에서 읽은 숫자를 문장으로 다시 적은 것뿐이다.
//
// 여기서 더하는 것 셋이다.
//
//   1. **우리 아이 기준 목표 대비** — 크기·나이로 정한 주간 목표(#341)의 몇 %인가
//   2. **빠진 요일** — 어느 요일에 못 나갔나
//   3. **지난주 대비** — 늘었나 줄었나
//
// 그리고 하나를 **제안**한다: 빠진 요일 + 자주 나가는 시간대. "다음 주엔 화요일 저녁 한 번
// 더 어때요."
//
// ## AI 라고 부르지 않는다
//
// 규칙으로 계산한 문장이다. #332 가 이 카드에서 "AI" 라는 이름과 "베타" 딱지를 뗐고, 이 파일은
// 그 자리를 채우되 이름을 되돌리지 않는다. LLM 두 문장은 2단계이고 키가 필요하다.
//
// ## 지어내지 않는다
//
// 모르는 것은 안 적는다. 목표가 없으면(고양이·기타) 달성률 줄이 없고, 지난주 기록이 없으면
// 비교 줄이 없다. **없는 줄을 그럴듯하게 채우면 그 문장이 곧 거짓말**이 된다.
library;

import 'walk_goal.dart';

/// 시간대 한 칸 — 계약의 `WalkStats.summary.byPartOfDay[]`.
class PartOfDayCount {
  /// `dawn` · `morning` · `afternoon` · `evening` 넷 중 하나.
  final String part;
  final int count;
  final double km;
  final int minutes;

  const PartOfDayCount({
    required this.part,
    required this.count,
    required this.km,
    required this.minutes,
  });

  /// 화면에 쓰는 이름. 모르는 값이면 `null` — 지어내지 않는다.
  String? get label => switch (part) {
        'dawn' => '새벽',
        'morning' => '아침',
        'afternoon' => '낮',
        'evening' => '저녁',
        _ => null,
      };

  static PartOfDayCount? tryParse(Object? json) {
    if (json is! Map) return null;
    final part = json['part'];
    if (part is! String || part.isEmpty) return null;
    return PartOfDayCount(
      part: part,
      count: (json['count'] as num?)?.toInt() ?? 0,
      km: (json['km'] as num?)?.toDouble() ?? 0,
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 서버가 준 계산 결과 — 계약의 `WalkStats.summary`.
///
/// **앱이 스스로 못 구하는 것만** 들어 있다. 빠진 요일은 `weekKm` 으로 세고, 달성률의
/// 목표는 기기에 있는 값이다(#341).
class WeekSummaryData {
  final double lastWeekKm;
  final int lastWeekMinutes;
  final int lastWeekCount;
  final List<PartOfDayCount> byPartOfDay;

  const WeekSummaryData({
    this.lastWeekKm = 0,
    this.lastWeekMinutes = 0,
    this.lastWeekCount = 0,
    this.byPartOfDay = const [],
  });

  static const empty = WeekSummaryData();

  /// 서버가 안 줬으면 [empty]. **null 을 위로 흘리지 않는다** — 화면이 두 갈래를 만들고
  /// 그중 하나가 언젠가 안 그린다.
  static WeekSummaryData parse(Object? json) {
    if (json is! Map) return empty;
    final raw = json['byPartOfDay'];
    return WeekSummaryData(
      lastWeekKm: (json['lastWeekKm'] as num?)?.toDouble() ?? 0,
      lastWeekMinutes: (json['lastWeekMinutes'] as num?)?.toInt() ?? 0,
      lastWeekCount: (json['lastWeekCount'] as num?)?.toInt() ?? 0,
      byPartOfDay: raw is List
          ? [for (final item in raw) PartOfDayCount.tryParse(item)]
              .whereType<PartOfDayCount>()
              .toList()
          : const [],
    );
  }

  /// 가장 많이 나간 시간대. 같은 횟수가 여럿이면 **이른 쪽**이다 — 순위를 지어내지 않고,
  /// 응답의 순서(새벽→저녁)가 곧 하루의 순서다.
  PartOfDayCount? get busiestPart {
    PartOfDayCount? best;
    for (final part in byPartOfDay) {
      if (part.count > 0 && (best == null || part.count > best.count)) {
        best = part;
      }
    }
    return best;
  }
}

/// 월~일 라벨. 서버의 `weekKm` 자리와 같은 순서다.
const List<String> kWeekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

/// "이번 주 요약" 한 장. 문장은 [lines] 다 — 화면은 그것을 이어 붙이기만 한다.
class WeeklySummary {
  /// 사실 문장들. **빈 목록일 수 있다**(기록이 하나도 없을 때는 [emptyLine] 을 쓴다).
  final List<String> lines;

  /// 다음 주 제안 한 줄. 만들 근거가 없으면 `null`.
  final String? suggestion;

  const WeeklySummary({required this.lines, this.suggestion});

  /// 기록이 없을 때의 한 줄. 숫자가 없으니 요약도 없다.
  static const String emptyLine = '이번 주는 아직 기록이 없어요. 오늘 한 바퀴 어때요.';

  /// 화면에 그릴 전체 글.
  String get text {
    final all = [...lines, if (suggestion != null) suggestion!];
    return all.isEmpty ? emptyLine : all.join(' ');
  }

  /// 계산 결과에서 문장을 만든다.
  ///
  /// [goal] 이 `null` 이면 달성률 줄이 없다 — 개가 아닌 아이에게는 산책 권장량 자료가
  /// 없어서 목표를 안 만든다(`WalkGoal.recommendedFor`).
  factory WeeklySummary.of({
    required int walkCount,
    required double totalKm,
    required List<double> weekKm,
    required List<int> weekMinutes,
    required WeekSummaryData summary,
    WalkGoal? goal,
  }) {
    if (walkCount == 0) {
      return const WeeklySummary(lines: []);
    }

    final minutes = weekMinutes.fold<int>(0, (sum, m) => sum + m);
    final lines = <String>[
      '이번 주 $walkCount회 · ${totalKm.toStringAsFixed(1)}km · $minutes분 걸었어요.',
    ];

    // ── 목표 대비 ──
    if (goal != null && goal.minutesPerWeek > 0) {
      final days = weekMinutes.where((m) => m > 0).length;
      final percent = (minutes * 100 / goal.minutesPerWeek).round();
      lines.add('목표는 주 ${goal.daysPerWeek}일 · ${goal.minutesPerWeek}분인데 '
          '$days일 · $minutes분, $percent% 예요.');
    }

    // ── 빠진 요일 ──
    //
    // **다 걸었으면 안 적는다.** "빠진 요일이 없어요" 는 사실이지만, 잘한 주에 굳이
    // 빠짐을 화제로 올릴 이유가 없다. 반대로 다섯 날 넘게 빠졌으면 요일을 나열하는 대신
    // 세어서 말한다 — 이름 여섯 개는 문장이 아니라 목록이다.
    final missing = [
      for (var i = 0; i < 7 && i < weekMinutes.length; i++)
        if (weekMinutes[i] == 0) kWeekdayNames[i],
    ];
    if (missing.isNotEmpty && missing.length <= 3) {
      lines.add('${missing.join('·')}요일엔 못 나갔어요.');
    }

    // ── 지난주 대비 ──
    //
    // 지난주 기록이 아예 없으면 비교하지 않는다. "지난주보다 6.2km 더 걸었어요" 는
    // 틀리진 않지만, 지난주에 앱을 안 쓴 사람에게는 뜻이 없는 말이다.
    if (summary.lastWeekCount > 0) {
      final diff = totalKm - summary.lastWeekKm;
      if (diff.abs() < 0.05) {
        lines.add('지난주와 비슷해요.');
      } else {
        final word = diff > 0 ? '더' : '적게';
        lines.add('지난주보다 ${diff.abs().toStringAsFixed(1)}km $word 걸었어요.');
      }
    }

    return WeeklySummary(
      lines: lines,
      suggestion: _suggest(missing: missing, summary: summary),
    );
  }

  /// "다음 주엔 화요일 저녁 한 번 더 어때요."
  ///
  /// **빠진 요일이 있고 자주 가는 시간대를 알 때만** 만든다. 둘 중 하나라도 없으면 제안이
  /// 아니라 짐작이 된다 — 매일 걸은 사람에게 "한 번 더" 는 할 말이 아니고, 시간대를 모르면
  /// 아무 때나 찍어 말하게 된다.
  static String? _suggest({
    required List<String> missing,
    required WeekSummaryData summary,
  }) {
    if (missing.isEmpty) return null;
    final part = summary.busiestPart?.label;
    if (part == null) return null;
    return '다음 주엔 ${missing.first}요일 $part에 한 번 더 어때요.';
  }
}

/// 서버가 모델로 만든 "AI 요약" (#486). 두 문장 + 제안 한 줄이 줄바꿈으로 온다.
///
/// null 이면 카드도 라벨도 없다 — 키가 없거나 · 실패 · 상한 · 숫자 검사에서 버린 경우이고, 그 자리는
/// [WeeklySummary](규칙 문장)가 그대로 맡는다. "AI" 라벨은 진짜 모델 문장에만 붙는다(#347 · #332).
class AiSummary {
  final String text;
  final DateTime? generatedAt;

  const AiSummary({required this.text, this.generatedAt});

  /// 계약의 `WalkStats.aiSummary` — 없거나 글이 비면 null.
  static AiSummary? parse(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final at = json['generatedAt'];
    return AiSummary(
      text: text.trim(),
      generatedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }

  /// 줄 단위 — 마지막 줄이 제안이다(서버 규칙: 첫 두 줄 요약, 셋째 줄 제안).
  List<String> get lines => text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}


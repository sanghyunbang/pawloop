import 'package:flutter/material.dart';
import 'package:heat_trip_flutter/core/mood/mood_color.dart';
import '../../domain/diary_entry.dart';

/// 감정 캘린더 + 연속 기록 스트릭 (F1-3).
///
/// 다이어리 기록(날짜 + 무드)을 이번 달 달력에 무드 색으로 칠하고,
/// 상단에 연속 기록 일수(스트릭)를 보여줍니다. 데이터가 없어도 빈 달력으로 안전.
class EmotionCalendarCard extends StatelessWidget {
  final List<DiaryEntry> entries;
  const EmotionCalendarCard({super.key, required this.entries});

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 날짜(YYYY-MM-DD) → 그 날 마지막 기록의 무드 키
  Map<DateTime, String> get _moodByDay {
    final map = <DateTime, String>{};
    for (final e in entries) {
      map[_d(e.date)] = e.moodLabel; // 같은 날 여러 건이면 마지막 것
    }
    return map;
  }

  /// 오늘(또는 어제까지 유예) 기준 연속 기록 일수.
  int get _streak {
    if (entries.isEmpty) return 0;
    final days = entries.map((e) => _d(e.date)).toSet();
    final today = _d(DateTime.now());
    var cursor = today;
    if (!days.contains(cursor)) {
      cursor = today.subtract(const Duration(days: 1)); // 오늘 미기록 시 어제부터
      if (!days.contains(cursor)) return 0;
    }
    var count = 0;
    while (days.contains(cursor)) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final moodByDay = _moodByDay;
    final streak = _streak;

    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leadingBlanks = first.weekday % 7; // 일요일=0 시작
    const weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(now.year, now.month, day);
      final mood = moodByDay[date];
      final isToday = day == now.day;
      cells.add(_DayCell(day: day, moodKey: mood, isToday: isToday));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${now.year}년 ${now.month}월 감정 캘린더',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2B2B34),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE7E0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 15,
                      color: Color(0xFFFB6A3E),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '연속 $streak일',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFB6A3E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final w in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: w == '일'
                            ? const Color(0xFFE07A7A)
                            : const Color(0xFF9A9AA4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: cells,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final String? moodKey;
  final bool isToday;
  const _DayCell({required this.day, this.moodKey, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final hasMood = moodKey != null;
    final fill = hasMood ? moodColor(moodKey) : Colors.transparent;
    return Container(
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: const Color(0xFFFB6A3E), width: 1.6)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 12,
          fontWeight: hasMood ? FontWeight.w800 : FontWeight.w500,
          color: hasMood ? Colors.white : const Color(0xFF8A8A92),
        ),
      ),
    );
  }
}

// lib/v2/data/weekly_report_reminder.dart
//
// 일요일 저녁 한 번, "이번 주 산책 정리가 준비됐어요" — #341 의 저녁 알림과 같은 길, #486 의 주간 요약을 보러 오라고.
//
// ## 푸시가 아니다
//
// 서버가 보내는 알림(#83, FCM)과 **아무 관계가 없다.** 기기 안에서 예약하고 기기가 띄운다 — 서버는
// 이 사람이 켰는지 모른다. 그래서 토큰도 동의도 새로 필요하지 않다(`walk_reminder.dart` 와 같은 판단).
//
// ## 왜 일요일 저녁인가
//
// 통계의 "이번 주" 는 월~일(KST)이다. 일요일 저녁이면 그 주의 산책이 거의 다 들어와 있고, 규칙 문장과
// AI 요약이 그 주를 정리한다 — 스트라바 · 애플 피트니스의 주간 정리도 주 끝에 온다. 시각은 저녁 산책
// 알림의 기본값과 같은 19:00 으로 고정한다 — 고를 것이 하나 늘면 설정이 그만큼 길어지고, 주 1회 알림에
// 그 값은 없다.
//
// ## 규칙이 순수 함수인 이유
//
// [nextWeeklyReportAt] 이 **시각을 인자로 받는다.** 가짜 시간으로 재는 테스트는 시계가 아니라 자기 자신을
// 재게 된다 — 이 저장소가 이미 밟은 함정이다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 켜 두었는가 — 그것 하나다. 시각은 [weeklyReportHour] 고정.
class WeeklyReportReminderSettings {
  const WeeklyReportReminderSettings({this.enabled = defaultEnabled});

  /// 기본은 꺼짐 — 묻지 않고 알림을 보내지 않는다(저녁 산책 알림과 같다).
  static const bool defaultEnabled = false;

  final bool enabled;

  Map<String, dynamic> toJson() => {'enabled': enabled};

  static WeeklyReportReminderSettings? tryParse(Object? json) {
    if (json is! Map) return null;
    return WeeklyReportReminderSettings(enabled: json['enabled'] == true);
  }

  @override
  bool operator ==(Object other) => other is WeeklyReportReminderSettings && other.enabled == enabled;

  @override
  int get hashCode => enabled.hashCode;
}

/// 설정이 바뀌면 오른다 — 예약을 다시 거는 조각([WeeklyReportReminderSync])이 듣는다.
final ValueNotifier<int> kWeeklyReportReminderRev = ValueNotifier<int>(0);

class WeeklyReportReminderStore {
  const WeeklyReportReminderStore();

  /// 설정이 남는 자리. **세션 것이다** — 로그아웃하면 지운다(#513).
  static const String key = 'v2.weekly_report_reminder';

  Future<WeeklyReportReminderSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const WeeklyReportReminderSettings();
    try {
      return WeeklyReportReminderSettings.tryParse(jsonDecode(raw)) ?? const WeeklyReportReminderSettings();
    } on FormatException {
      return const WeeklyReportReminderSettings();
    }
  }

  Future<void> save(WeeklyReportReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(settings.toJson()));
    kWeeklyReportReminderRev.value++;
  }
}

/// 일요일 저녁 7시.
const int weeklyReportHour = 19;

/// 다음에 울릴 시각 — **다가오는 일요일 19:00**(기기 시간대). 오늘이 일요일이고 아직 19:00 전이면 오늘이다.
/// 꺼져 있으면 null.
DateTime? nextWeeklyReportAt({required bool enabled, required DateTime now}) {
  if (!enabled) return null;
  final daysToSunday = (DateTime.sunday - now.weekday) % 7; // 0 이면 오늘이 일요일
  final candidate = DateTime(now.year, now.month, now.day + daysToSunday, weeklyReportHour);
  if (candidate.isAfter(now)) return candidate;
  // 오늘이 일요일인데 19:00 이 지났다 — 다음 일요일.
  return DateTime(candidate.year, candidate.month, candidate.day + 7, weeklyReportHour);
}

/// 예약의 그릇 — 진짜는 `LocalNotificationSink`. 이름을 산책 알림과 다르게 둔 것은 한 클래스가 둘을 함께
/// 구현하기 때문이다(같은 이름이면 서로를 덮는다).
abstract class WeeklyReportReminderSink {
  Future<void> cancelWeeklyReport();
  Future<void> scheduleWeeklyReportAt(DateTime at, {required String title, required String body});
}

/// 설정을 읽고 예약을 다시 거는 것 — 화면과 설정 타일이 부른다.
class WeeklyReportReminder {
  const WeeklyReportReminder({required this.sink, this.store = const WeeklyReportReminderStore()});

  final WeeklyReportReminderSink sink;
  final WeeklyReportReminderStore store;

  /// 숫자 · 이름 없이 — 문장은 통계 화면이 그때 서버에서 읽는다. 알림에 숫자를 넣으면 예약한 날의 숫자다.
  static const title = '이번 주 산책 정리가 준비됐어요';
  static const body = '통계에서 이번 주 요약과 다음 주 제안을 볼 수 있어요';

  /// 지우고, 켜져 있으면 다음 일요일 19:00 에 다시 건다. 건 시각을 돌려준다(꺼져 있으면 null).
  Future<DateTime?> refresh({DateTime? now}) async {
    final settings = await store.read();
    final at = nextWeeklyReportAt(enabled: settings.enabled, now: now ?? DateTime.now());
    await sink.cancelWeeklyReport();
    if (at == null) return null;
    await sink.scheduleWeeklyReportAt(at, title: title, body: body);
    return at;
  }
}

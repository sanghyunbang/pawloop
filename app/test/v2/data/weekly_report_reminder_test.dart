// 일요일 저녁 주간 정리 알림 — 언제 울릴까(순수 함수), 켜고 끄면 무엇이 걸리나. 시각은 인자로 흘린다(가짜 시간 아님).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/weekly_report_reminder.dart';

class _FakeSink implements WeeklyReportReminderSink {
  int cancels = 0;
  final List<({DateTime at, String title, String body})> scheduled = [];

  @override
  Future<void> cancelWeeklyReport() async => cancels++;

  @override
  Future<void> scheduleWeeklyReportAt(DateTime at, {required String title, required String body}) async =>
      scheduled.add((at: at, title: title, body: body));
}

void main() {
  group('언제 울릴까', () {
    // 2026-09-13 은 일요일, 09-14 는 월요일이다.
    final sunday = DateTime(2026, 9, 13);

    test('꺼져 있으면 안 건다', () {
      expect(nextWeeklyReportAt(enabled: false, now: DateTime(2026, 9, 14, 10)), isNull);
    });

    test('기본은 꺼짐이다 — 묻지 않고 알림을 보내지 않는다', () {
      expect(const WeeklyReportReminderSettings().enabled, isFalse);
      expect(weeklyReportHour, 19);
    });

    test('월요일이면 다가오는 일요일 19:00', () {
      expect(nextWeeklyReportAt(enabled: true, now: DateTime(2026, 9, 14, 10)), DateTime(2026, 9, 20, 19));
    });

    test('토요일 밤이면 다음 날(일요일) 19:00', () {
      expect(nextWeeklyReportAt(enabled: true, now: DateTime(2026, 9, 19, 23, 30)), DateTime(2026, 9, 20, 19));
    });

    test('일요일 19:00 전이면 오늘 19:00', () {
      expect(nextWeeklyReportAt(enabled: true, now: sunday.add(const Duration(hours: 18, minutes: 59))),
          DateTime(2026, 9, 13, 19));
    });

    test('일요일 19:00 이 지났으면 다음 일요일 — 오늘 것을 다시 걸면 곧바로 울린다', () {
      expect(nextWeeklyReportAt(enabled: true, now: sunday.add(const Duration(hours: 19))), DateTime(2026, 9, 20, 19));
      expect(nextWeeklyReportAt(enabled: true, now: sunday.add(const Duration(hours: 22))), DateTime(2026, 9, 20, 19));
    });

    test('월말을 넘어도 날짜가 맞는다', () {
      // 2026-09-29 화요일 → 10-04 일요일
      expect(nextWeeklyReportAt(enabled: true, now: DateTime(2026, 9, 29, 8)), DateTime(2026, 10, 4, 19));
    });
  });

  group('refresh', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('켜져 있으면 지우고 다시 건다 — 제목에도 본문에도 숫자가 없다', () async {
      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: true));
      final sink = _FakeSink();

      final at = await WeeklyReportReminder(sink: sink).refresh(now: DateTime(2026, 9, 14, 10));

      expect(at, DateTime(2026, 9, 20, 19));
      expect(sink.cancels, 1);
      expect(sink.scheduled.single.at, DateTime(2026, 9, 20, 19));
      expect(sink.scheduled.single.title, '이번 주 산책 정리가 준비됐어요');
      expect(sink.scheduled.single.body.contains(RegExp(r'\d')), isFalse,
          reason: '알림에 숫자를 넣으면 예약한 날의 숫자다 — 문장은 화면이 그때 읽는다');
    });

    test('꺼져 있으면 지우기만 한다', () async {
      final sink = _FakeSink();

      final at = await WeeklyReportReminder(sink: sink).refresh(now: DateTime(2026, 9, 14, 10));

      expect(at, isNull);
      expect(sink.cancels, 1);
      expect(sink.scheduled, isEmpty);
    });
  });

  group('저장', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('저장한 값을 다시 읽고, 저장할 때마다 rev 가 오른다', () async {
      const store = WeeklyReportReminderStore();
      final before = kWeeklyReportReminderRev.value;

      await store.save(const WeeklyReportReminderSettings(enabled: true));

      expect((await store.read()).enabled, isTrue);
      expect(kWeeklyReportReminderRev.value, before + 1);
    });

    test('깨진 값은 기본값으로 읽는다', () async {
      SharedPreferences.setMockInitialValues({'v2.weekly_report_reminder': '{not json'});

      expect((await const WeeklyReportReminderStore().read()).enabled, isFalse);
    });
  });
}

// 일요일 저녁 주간 정리 — 설정 타일(켜면 권한 → 저장 → 예약, 거절이면 되돌림)과 홈의 예약 조각.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/weekly_report_reminder.dart';
import 'package:heat_trip_flutter/v2/widgets/weekly_report_reminder_sync.dart';
import 'package:heat_trip_flutter/v2/widgets/weekly_report_reminder_tile.dart';

class _FakeSink implements WeeklyReportReminderSink {
  int cancels = 0;
  final List<DateTime> scheduled = [];

  @override
  Future<void> cancelWeeklyReport() async => cancels++;

  @override
  Future<void> scheduleWeeklyReportAt(DateTime at, {required String title, required String body}) async =>
      scheduled.add(at);
}

final _monday = DateTime(2026, 9, 14, 10);

Future<_FakeSink> _pumpTile(WidgetTester tester, {bool granted = true}) async {
  final sink = _FakeSink();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WeeklyReportReminderTile(sink: sink, requestPermission: () async => granted, now: _monday),
    ),
  ));
  await tester.pumpAndSettle();
  return sink;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('설정 타일', () {
    testWidgets('처음에는 꺼져 있다 — 묻지 않고 알림을 보내지 않는다', (tester) async {
      final sink = await _pumpTile(tester);

      expect(find.text('일요일 저녁 주간 정리'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('weekly-report-switch'))).value, isFalse);
      expect(sink.scheduled, isEmpty);
    });

    testWidgets('켜면 저장되고 다가오는 일요일 19:00 에 걸린다', (tester) async {
      final sink = await _pumpTile(tester);

      await tester.tap(find.byKey(const Key('weekly-report-switch')));
      await tester.pumpAndSettle();

      expect((await const WeeklyReportReminderStore().read()).enabled, isTrue);
      expect(sink.scheduled, [DateTime(2026, 9, 20, 19)]);
    });

    testWidgets('권한을 거절당하면 스위치가 되돌아가고 이유를 말한다', (tester) async {
      final sink = await _pumpTile(tester, granted: false);

      await tester.tap(find.byKey(const Key('weekly-report-switch')));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byKey(const Key('weekly-report-switch'))).value, isFalse);
      expect((await const WeeklyReportReminderStore().read()).enabled, isFalse);
      expect(sink.scheduled, isEmpty);
      expect(find.text('기기 설정에서 알림을 허용해 주세요'), findsOneWidget);
    });

    testWidgets('끄면 예약이 지워진다', (tester) async {
      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: true));
      final sink = await _pumpTile(tester);

      await tester.tap(find.byKey(const Key('weekly-report-switch')));
      await tester.pumpAndSettle();

      expect((await const WeeklyReportReminderStore().read()).enabled, isFalse);
      expect(sink.cancels, 1);
      expect(sink.scheduled, isEmpty);
    });
  });

  group('홈의 예약 조각', () {
    testWidgets('켜져 있으면 앱을 열 때 한 번 건다 — 다시 그려도 같은 값으로 또 걸지 않는다', (tester) async {
      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: true));
      final sink = _FakeSink();

      await tester.pumpWidget(MaterialApp(home: WeeklyReportReminderSync(guest: false, sink: sink, now: _monday)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: WeeklyReportReminderSync(guest: false, sink: sink, now: _monday)));
      await tester.pumpAndSettle();

      expect(sink.scheduled, [DateTime(2026, 9, 20, 19)]);
    });

    testWidgets('설정이 바뀌면 다시 건다 — 끄면 지워진다', (tester) async {
      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: true));
      final sink = _FakeSink();
      await tester.pumpWidget(MaterialApp(home: WeeklyReportReminderSync(guest: false, sink: sink, now: _monday)));
      await tester.pumpAndSettle();

      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: false));
      await tester.pumpAndSettle();

      expect(sink.cancels, 2);
      expect(sink.scheduled, hasLength(1), reason: '두 번째 refresh 는 지우기만');
    });

    testWidgets('게스트에게는 걸지 않는다', (tester) async {
      await const WeeklyReportReminderStore().save(const WeeklyReportReminderSettings(enabled: true));
      final sink = _FakeSink();

      await tester.pumpWidget(MaterialApp(home: WeeklyReportReminderSync(guest: true, sink: sink, now: _monday)));
      await tester.pumpAndSettle();

      expect(sink.cancels, 0);
      expect(sink.scheduled, isEmpty);
    });
  });
}

// 설정의 "저녁 산책 알림" 줄 — 이슈 #341.
//
// 스위치를 켜는 순간에만 권한을 묻고, **거절당하면 되돌린다.** 켜진 채로 두면 사용자는
// "켰는데 안 온다" 를 겪고 그건 앱이 고장 난 것으로 읽힌다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_reminder.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_reminder_tile.dart';

class _FakeSink implements WalkReminderSink {
  int cancels = 0;
  final List<DateTime> scheduled = [];

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<void> scheduleAt(DateTime at, {required String title, required String body}) async =>
      scheduled.add(at);
}

Future<_FakeSink> _pump(
  WidgetTester tester, {
  bool granted = true,
  int todayWalkCount = 0,
}) async {
  final sink = _FakeSink();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WalkReminderTile(
        sink: sink,
        requestPermission: () async => granted,
        todayWalkCount: () async => todayWalkCount,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return sink;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('처음에는 꺼져 있고 시각 줄이 없다 — 묻지 않고 알림을 보내지 않는다', (tester) async {
    await _pump(tester);

    expect(find.text('저녁 산책 알림'), findsOneWidget);
    expect(find.text('알림 시각'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('켜면 저장되고 예약이 걸리고 시각 줄이 나온다', (tester) async {
    final sink = await _pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect((await const WalkReminderStore().read()).enabled, isTrue);
    expect(sink.scheduled, hasLength(1));
    expect(find.text('알림 시각'), findsOneWidget);
    expect(find.text('오후 7:00'), findsOneWidget);
  });

  testWidgets('권한을 거절당하면 스위치가 되돌아가고 이유를 말한다', (tester) async {
    final sink = await _pump(tester, granted: false);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse,
        reason: '켜진 채로 두면 "켰는데 안 온다" 가 된다');
    expect((await const WalkReminderStore().read()).enabled, isFalse);
    expect(sink.scheduled, isEmpty);
    expect(find.text('기기 설정에서 알림을 허용해 주세요'), findsOneWidget);
  });

  testWidgets('오늘 이미 걸었으면 켜도 오늘 것이 안 걸린다 — 내일로 간다', (tester) async {
    final sink = await _pump(tester, todayWalkCount: 2);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // 날짜로 비교하면 자정을 넘기는 순간에 흔들린다 — "앞으로" 와 "그 시각" 으로 잰다.
    final at = sink.scheduled.single;
    expect(at.isAfter(DateTime.now()), isTrue,
        reason: '이미 걸은 날 저녁에 울리면 그건 틀린 알림이다');
    expect(at.hour, 19);
  });

  testWidgets('끄면 예약이 지워지고 시각 줄이 사라진다 (완료 조건 4)', (tester) async {
    await const WalkReminderStore()
        .save(const WalkReminderSettings(enabled: true, hour: 19));
    final sink = await _pump(tester);

    expect(find.text('알림 시각'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect((await const WalkReminderStore().read()).enabled, isFalse);
    expect(sink.cancels, greaterThan(0));
    expect(sink.scheduled, isEmpty);
    expect(find.text('알림 시각'), findsNothing);
  });
}

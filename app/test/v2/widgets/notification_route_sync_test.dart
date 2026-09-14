// 눌린 알림을 한 번 보내는 조각 (#486 후속) — 이미 와 있던 것 · 떠 있는 동안 눌린 것 · 두 번 가지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/notification_route.dart';
import 'package:heat_trip_flutter/v2/widgets/notification_route_sync.dart';

Future<List<NotificationDestination>> _pump(WidgetTester tester) async {
  final gone = <NotificationDestination>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: NotificationRouteSync(onGo: (_, d) => gone.add(d))),
  ));
  await tester.pumpAndSettle();
  return gone;
}

void main() {
  setUp(NotificationRouteInbox.resetForTest);
  tearDown(NotificationRouteInbox.resetForTest);

  testWidgets('꺼져 있던 앱이 알림으로 떴으면 — 홈이 그려진 뒤 그리로 간다', (tester) async {
    NotificationRouteInbox.offer(NotificationDestination.weeklyReport);

    final gone = await _pump(tester);

    expect(gone, [NotificationDestination.weeklyReport]);
    expect(NotificationRouteInbox.pending.value, isNull, reason: '가져갔으면 비운다');
  });

  testWidgets('앱이 떠 있는 동안 누른 알림도 간다', (tester) async {
    final gone = await _pump(tester);
    expect(gone, isEmpty);

    NotificationRouteInbox.offer(NotificationDestination.schedule);
    await tester.pumpAndSettle();

    expect(gone, [NotificationDestination.schedule]);
  });

  testWidgets('다시 그려져도 두 번 가지 않는다 — 다른 탭에 머물 수 있어야 한다', (tester) async {
    NotificationRouteInbox.offer(NotificationDestination.home);
    final gone = await _pump(tester);

    await tester.pump();
    await tester.pumpAndSettle();

    expect(gone, [NotificationDestination.home]);
  });

  testWidgets('누른 알림이 없으면 아무 데도 안 간다', (tester) async {
    final gone = await _pump(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(gone, isEmpty);
  });
}

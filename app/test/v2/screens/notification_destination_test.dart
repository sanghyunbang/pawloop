// 알림이 가리키는 곳으로 실제로 가는가 (#486 후속) — 탭이 바뀌고, 주간 정리는 통계 화면이 열린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/notification_route.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';

/// 셸을 통째로 띄우지 않는다 — 여기서 재는 것은 "가는 것" 하나다. 버튼을 눌러 그 자리의 context 로 부른다.
Future<void> _pump(WidgetTester tester, NotificationDestination destination) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => goToNotificationDestination(context, destination),
          child: const Text('가기'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('가기'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 통계 화면이 진짜로 열리는지만 재는 테스트다 — 로그인 전(게스트)이면 서버를 부르지 않는다.
    AuthState.status.value = AuthStatus.unauthenticated;
    RootTab.index.value = 3; // 커뮤니티에 있다가 알림을 눌렀다고 둔다.
  });
  tearDown(() {
    AuthState.resetForTest();
    RootTab.index.value = 0;
  });

  testWidgets('저녁 산책 알림 → 홈 탭, 화면은 안 얹는다', (tester) async {
    await _pump(tester, NotificationDestination.home);

    expect(RootTab.index.value, 0);
    expect(find.byType(InsightScreen), findsNothing);
  });

  testWidgets('일정 알림 → 일정 탭', (tester) async {
    await _pump(tester, NotificationDestination.schedule);

    expect(RootTab.index.value, 2);
    expect(find.byType(InsightScreen), findsNothing);
  });

  testWidgets('주간 정리 알림 → 홈 탭 위에 통계 화면', (tester) async {
    await _pump(tester, NotificationDestination.weeklyReport);

    expect(RootTab.index.value, 0);
    expect(find.byType(InsightScreen), findsOneWidget);
  });

  testWidgets('두 번 눌러도 통계가 두 장 쌓이지 않는다 — 뒤로 가기 한 번이면 돌아온다', (tester) async {
    await _pump(tester, NotificationDestination.weeklyReport);

    // 같은 알림을 한 번 더. 앞의 화면을 닫고 다시 연다.
    final context = tester.element(find.byType(InsightScreen));
    goToNotificationDestination(context, NotificationDestination.weeklyReport);
    await tester.pumpAndSettle();

    expect(find.byType(InsightScreen), findsOneWidget);
    expect(find.text('가기'), findsNothing, reason: '통계가 위에 있다');

    Navigator.of(tester.element(find.byType(InsightScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text('가기'), findsOneWidget, reason: '한 번만 뒤로 가면 원래 자리다');
  });
}

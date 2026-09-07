// 홈의 "급할 때" 한 줄 — 두 번 만에 전화까지 (#337).
//
// 페르소나 P1 의 실패비용이 "아플 때 근처 병원을 못 찾음" 이다. 홈에서 지도 탭 → 병원 칩 →
// 목록에서 찾기까지 가면 그 순간에는 늦다. 이 테스트는 **진입이 홈에 있다**는 것을 지킨다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('홈에 "급할 때 · 가까운 동물병원" 이 있다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
    await tester.pumpAndSettle();

    expect(find.text('급할 때 · 가까운 동물병원'), findsOneWidget);
    expect(find.byIcon(Icons.local_hospital_rounded), findsOneWidget);
  });
}

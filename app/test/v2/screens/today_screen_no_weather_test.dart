// 홈에 하드코딩 날씨 카드가 없다 (#326).
//
// "맑음 · 24°C · 미세먼지 보통" 이 새벽 3시에도 홈 한가운데 있었다. 진짜 값이 오기 전까지는
// 카드 자체가 없어야 한다 — 진짜 값은 #336(산책 안전 지수)이 가져온다.
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

  testWidgets('홈 어디에도 "°C" 와 "산책하기 좋은 날씨" 가 없다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('°C'), findsNothing);
    expect(find.textContaining('산책하기 좋은 날씨'), findsNothing);
    expect(find.textContaining('미세먼지'), findsNothing);
  });
}

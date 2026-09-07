// 온보딩이 동네를 한 번 권한다 — 이슈 #342 (무엇을 4).
//
// **건너뛸 수 있어야 한다.** 이 화면은 "구경만 하려는 사람을 가두지 않는다" 가 원칙이라
// (반려동물 등록도 강제하지 않는다), 동네도 같은 규칙을 따른다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/onboarding_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: '새사람'));
  });
  tearDown(() {
    AuthState.resetForTest();
    kMyPets.value = const [];
  });

  testWidgets('"나중에 할래요" 는 동네를 안 묻고 온보딩을 끝낸다', (tester) async {
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(openNeighborhood: (_) async => asked++),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('나중에 할래요'));
    await tester.pumpAndSettle();

    expect(asked, 0, reason: '구경만 하려는 사람을 두 화면에 가두지 않는다');
  });

  testWidgets('아이를 등록하지 않고 시트를 닫으면 동네도 안 묻는다', (tester) async {
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(openNeighborhood: (_) async => asked++),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('우리 아이 등록하기'));
    await tester.pumpAndSettle();
    // 등록 시트를 그냥 닫는다.
    Navigator.of(tester.element(find.byType(OnboardingScreen))).maybePop();
    await tester.pumpAndSettle();

    expect(asked, 0,
        reason: '등록을 안 한 사람에게 동네까지 물으면 화면 셋을 연달아 밀어붙이는 셈이다');
  });
}

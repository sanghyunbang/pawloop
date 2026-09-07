// 반려동물 등록 권유 — 없는 "추천" 을 약속하지 않는다 (#325).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/onboarding_screen.dart';

void main() {
  setUp(() => AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker')));
  tearDown(AuthState.resetForTest);

  testWidgets('권유 문구에 "추천" 이 없고, 기록이 아이 이름으로 쌓인다고 말한다', (t) async {
    await t.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await t.pumpAndSettle();

    expect(find.textContaining('추천'), findsNothing, reason: '추천 기능이 없다 — 있는 것만 약속한다');
    expect(find.textContaining('우리 아이 이름으로 쌓여요'), findsOneWidget);
  });
}

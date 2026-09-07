// 내 프로필 — 게스트 (#324).
//
// 주 버튼이 "우리 아이 등록하기"(로그인 없이는 안 된다)였고 "로그인하지 않았어요" 는
// 회색 한 줄이었다. 이제 주 버튼이 로그인이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('게스트의 주 버튼은 "로그인 / 회원가입" 이고 등록 버튼은 없다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;

    await tester.pumpWidget(const MaterialApp(home: MeScreen()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '로그인 / 회원가입'), findsOneWidget);
    expect(find.text('우리 아이 등록하기'), findsNothing);
    expect(find.text('로그인하면 우리 아이가 여기 있어요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '로그인 / 회원가입'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('로그인했는데 아이가 없으면 등록이 주 버튼이다', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));

    await tester.pumpWidget(const MaterialApp(home: MeScreen()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '우리 아이 등록하기'), findsOneWidget);
    expect(find.text('아직 등록된 아이가 없어요'), findsOneWidget);
  });
}

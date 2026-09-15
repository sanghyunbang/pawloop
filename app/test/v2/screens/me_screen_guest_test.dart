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
    // **서버가 "아이 없음" 이라고 답한 상태로 둔다**(#568). 안 두면 "아직 안 읽음" 이라
    // 화면이 조용하다 — 읽어 보지도 않고 "없어요" 라고 말하면 안 되기 때문이다.
    replacePets(const []);

    await tester.pumpWidget(const MaterialApp(home: MeScreen()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '우리 아이 등록하기'), findsOneWidget);
    expect(find.text('아직 등록된 아이가 없어요'), findsOneWidget);
  });

  testWidgets('로그인했는데 아이가 없어도 설정과 로그아웃이 있다 — 등록 안내뿐이면 계정을 못 바꾼다(#371)',
      (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    await tester.pumpWidget(const MaterialApp(home: MeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('게스트의 빈 프로필에는 로그아웃이 없다 — 설정은 있다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    await tester.pumpWidget(const MaterialApp(home: MeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('로그아웃'), findsNothing, reason: '로그인한 적이 없다');
    // 전에는 설정도 없었다. 그래서 그냥 둘러보는 사람은 **약관도 내 동네도 알림도**
    // 열 방법이 없었다(#404). 셋 다 로그인과 상관없는 값이라 길을 열었다.
    expect(find.text('설정'), findsOneWidget);
  });
}

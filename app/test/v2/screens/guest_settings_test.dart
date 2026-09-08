// 게스트도 설정에 닿는다 — 이슈 #404.
//
// ## 왜 이게 중요한가
//
// 게스트 프로필에는 "로그인 / 회원가입" 버튼 하나뿐이었다. 그래서 그냥 둘러보는 사람은
// **약관도, 내 동네도, 저녁 알림도** 열 방법이 없었다.
//
//  - **약관**은 스토어가 앱 안에서 볼 수 있기를 요구한다(#165 가 같은 문제의 로그인 버전).
//  - **내 동네**(#342)는 사용자가 목록에서 고르는 값이고 기기에 산다. 게스트가 골라도
//    지도의 첫 화면이 그 동네가 된다 — 서버 요청만 조용히 실패한다.
//  - **저녁 알림**(#341)은 기기 안 예약이라 계정과 무관하다.
//
// 로그아웃만 없다. 로그인한 적이 없기 때문이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';
import 'package:heat_trip_flutter/v2/screens/settings_screen.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
    kMyPets.value = const [];
    AuthState.resetForTest();
  });
  tearDown(AuthState.resetForTest);

  group('게스트 프로필', () {
    setUp(() => AuthState.status.value = AuthStatus.unauthenticated);

    testWidgets('설정으로 가는 줄이 있다 — 없으면 약관을 볼 길이 없다', (tester) async {
      await _pump(tester, const MeScreen());

      expect(find.text('설정'), findsOneWidget);
      expect(find.text('로그인 / 회원가입'), findsOneWidget);
    });

    testWidgets('로그아웃은 없다 — 로그인한 적이 없다', (tester) async {
      await _pump(tester, const MeScreen());

      expect(find.text('로그아웃'), findsNothing);
    });
  });

  group('게스트 설정 화면', () {
    setUp(() => AuthState.status.value = AuthStatus.unauthenticated);

    testWidgets('약관 · 내 동네 · 알림 · 앱 넷은 그대로 보인다', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('약관 및 정책'), findsOneWidget);
      expect(find.text('개인정보처리방침'), findsOneWidget,
          reason: '스토어가 앱 안에서 볼 수 있기를 요구한다(#165)');
      expect(find.text('내 동네'), findsOneWidget);
      expect(find.text('알림'), findsOneWidget);
      expect(find.text('앱'), findsOneWidget);
    });

    testWidgets('계정 절은 없다 — 지울 계정이 없다', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('계정'), findsNothing);
      expect(find.text('회원 탈퇴'), findsNothing);
    });
  });

  group('로그인한 사람', () {
    setUp(() => AuthState.signInForTest(const AuthUser(id: 1, nickname: '반려인')));

    testWidgets('설정과 로그아웃이 둘 다 있다 — 예전 그대로다(#371)', (tester) async {
      await _pump(tester, const MeScreen());

      expect(find.text('설정'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('설정 화면에 계정 절이 있다', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('계정'), findsOneWidget);
      expect(find.text('회원 탈퇴'), findsOneWidget);
    });
  });
}

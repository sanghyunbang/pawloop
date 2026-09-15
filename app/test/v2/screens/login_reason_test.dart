// 게스트가 막힌 이유는 **로그인 화면이 들고 있는다** — 이슈 #517.
//
// 예전에는 부르는 쪽이 스낵바로 말하고 곧바로 로그인 화면을 밀어 올렸다. 스낵바는 1.6초
// 뒤 사라지고 전환 애니메이션이 그중 0.3초를 먹는다 — 걸으러 온 사람은 로그인 화면을
// 보면서 "내가 뭘 눌렀더라" 를 다시 떠올려야 했다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AuthState.resetForTest);

  testWidgets('이유를 주면 로그인 화면이 그것을 그린다', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: LoginScreen(showAppleSignIn: false, reason: '로그인하면 산책 기록이 남아요'),
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('login-reason')), findsOneWidget);
    expect(find.text('로그인하면 산책 기록이 남아요'), findsOneWidget);
  });

  testWidgets('이유가 없으면 그 자리도 없다 — 빈 알약을 그리지 않는다', (t) async {
    await t.pumpWidget(const MaterialApp(home: LoginScreen(showAppleSignIn: false)));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('login-reason')), findsNothing);
  });

  testWidgets('게스트가 산책 시작을 누르면 이유를 든 로그인 화면이 뜬다', (t) async {
    AuthState.status.value = AuthStatus.unauthenticated;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => startWalk(context),
              child: const Text('산책 시작'),
            ),
          ),
        ),
      ),
    ));

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('로그인하면 산책 기록이 남아요'), findsOneWidget,
        reason: '스낵바로 스쳐 지나가면 로그인 화면 앞에서 이유를 잊는다');
  });
}

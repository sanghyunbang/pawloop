// 홈 — 게스트 (#324).
//
// 첫 실행의 게스트 홈이 "기록을 불러오지 못했어요" 와 "다시 로그인해 주세요" 를 보여 줬다.
// 둘 다 401 을 오류로 그린 것이다. 이제 홈은 게스트에게 "로그인하면" 을 말하고 서버를
// 부르지 않는다. 이 테스트는 **진짜 위젯 트리**(TodayScreen 전체)를 띄운다 — 카드 하나만
// 고쳐 놓고 홈에서 다른 카드가 여전히 401 을 말하는 회귀를 잡기 위해서다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

Future<void> _pumpGuestHome(WidgetTester tester) async {
  AuthState.resetForTest();
  AuthState.status.value = AuthStatus.unauthenticated;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('게스트 홈에는 "다시 로그인" 도 "불러오지 못했어요" 도 없다', (tester) async {
    await _pumpGuestHome(tester);

    expect(find.textContaining('다시 로그인'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.text('로그인하면 오늘 산책이 여기 쌓여요'), findsOneWidget);
    expect(find.text('로그인하면 가족과 오늘의 케어를 나눠요'), findsOneWidget);
    expect(find.text('t'), findsNothing, reason: '아바타 리터럴');
  });

  // ─────────────────────── 기록·통계로 가는 문 (#708) ───────────────────────
  //
  // 문 둘은 로그인한 사람의 것이다. 게스트의 기록·통계 화면은 어차피 전부 0 이고, 요약
  // 카드는 바로 위에서 이미 "로그인하면 오늘 산책이 여기 쌓여요" 를 말하고 있다.

  testWidgets('게스트 홈에는 "내 산책 기록" 도 "산책 통계" 도 없다', (tester) async {
    await _pumpGuestHome(tester);

    expect(find.text('내 산책 기록'), findsNothing);
    expect(find.text('산책 통계'), findsNothing);
  });

  testWidgets('게스트가 요약 카드를 눌러도 통계 화면이 안 열린다', (tester) async {
    // **지금 막은 구멍이다.** 예전에는 요약 카드 전체가 `InsightScreen` 으로 가는 손이었다
    // (`today_screen.dart` 173줄). 셰브론도 글자도 없어서 누를 수 있는 줄 몰랐을 뿐,
    // 게스트가 카드를 건드리면 0 만 가득한 통계 화면이 열렸다 — `insight_screen.dart` 에도
    // `myrecords_screen.dart` 에도 로그인 가드가 한 줄도 없다.
    await _pumpGuestHome(tester);

    final card = find.byKey(const Key('walk-summary'));
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.byType(InsightScreen), findsNothing,
        reason: '로그인 안 한 사람에게 0 만 가득한 통계 화면을 보여 주지 않는다');
    expect(find.byType(MyRecordsScreen), findsNothing);
    expect(find.text('로그인하면 오늘 산책이 여기 쌓여요'), findsOneWidget,
        reason: '눌러도 홈 그대로다');
  });
}

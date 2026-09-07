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
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
  });
  tearDown(AuthState.resetForTest);

  testWidgets('게스트 홈에는 "다시 로그인" 도 "불러오지 못했어요" 도 없다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TodayScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('다시 로그인'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.text('로그인하면 오늘 산책이 여기 쌓여요'), findsOneWidget);
    expect(find.text('로그인하면 가족과 오늘의 케어를 나눠요'), findsOneWidget);
    expect(find.text('t'), findsNothing, reason: '아바타 리터럴');
  });
}

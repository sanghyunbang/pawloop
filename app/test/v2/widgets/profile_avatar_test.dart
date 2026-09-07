// 우상단 아바타 — 예전엔 모두에게 글자 't' 하나였다 (#324).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/widgets/profile_avatar.dart';

// const 로 두면 같은 위젯이라 다시 그리지 않는다 — 두 번째 pump 가 첫 사람을 남긴다.
Widget _wrap() => MaterialApp(
      key: UniqueKey(),
      home: const Scaffold(body: ProfileAvatar(tappable: false)),
    );

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('로그인 전에는 사람 아이콘이고 글자가 없다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    await tester.pumpWidget(_wrap());

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.text('t'), findsNothing);
  });

  testWidgets('로그인하면 닉네임 첫 글자 — walker 는 W, 보리맘은 보', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    await tester.pumpWidget(_wrap());
    expect(find.text('W'), findsOneWidget);
    expect(find.text('t'), findsNothing);

    // 같은 authenticated 상태에서 사람만 바뀌면 알림이 없다 — 실제로는 로그아웃을 거친다.
    AuthState.signInForTest(const AuthUser(id: 2, nickname: '보리맘'));
    await tester.pumpWidget(_wrap());
    expect(find.text('보'), findsOneWidget);
  });

  testWidgets('로그인했는데 닉네임이 비어 있으면 아이콘이다 — 빈 글자를 그리지 않는다', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 3, nickname: '  '));
    await tester.pumpWidget(_wrap());
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });
}

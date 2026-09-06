// 첫 실행 소개 — 화면과 게이트. 이슈 #323.
//
// ## 여기서 재는 것
//
//  1. 세 장이 순서대로 넘어가고, 마지막 장의 버튼만 "시작하기" 다.
//  2. 건너뛰기와 시작하기가 **둘 다** onDone 을 한 번씩만 부른다 — 연타해도 한 번.
//  3. 게이트: 처음엔 안 봤고, 적으면 봤고, 지우면 다시 안 봤다.
//  4. 세 장 어디에도 시스템 이모지 글자가 없다 — 디자인 시스템은 Fluent 3D 자산이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/intro_gate.dart';
import 'package:heat_trip_flutter/v2/screens/intro_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IntroScreen', () {
    testWidgets('첫 장이 보이고, 버튼은 "다음", 건너뛰기가 있다', (tester) async {
      await tester.pumpWidget(_wrap(IntroScreen(onDone: () {})));

      expect(find.text(kIntroPages.first.title), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget);
      expect(find.text('시작하기'), findsNothing);
    });

    testWidgets('"다음" 을 두 번 누르면 마지막 장이고 버튼이 "시작하기" 로 바뀐다',
        (tester) async {
      await tester.pumpWidget(_wrap(IntroScreen(onDone: () {})));

      for (var i = 0; i < kIntroPages.length - 1; i++) {
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();
      }

      expect(find.text(kIntroPages.last.title), findsOneWidget);
      expect(find.text('시작하기'), findsOneWidget);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('마지막 장의 "시작하기" 는 onDone 을 한 번 부른다 — 연타해도 한 번',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(IntroScreen(onDone: () => calls++)));

      for (var i = 0; i < kIntroPages.length - 1; i++) {
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('시작하기'));
      await tester.tap(find.text('시작하기'));
      await tester.pump();

      expect(calls, 1, reason: '두 번 불리면 라우터의 go 가 두 번 돈다');
    });

    testWidgets('"건너뛰기" 도 onDone 을 부른다 — 어느 장에서든', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(IntroScreen(onDone: () => calls++)));

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('건너뛰기'));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('설정에서 다시 볼 때는 "닫기" 다', (tester) async {
      await tester.pumpWidget(_wrap(IntroScreen(onDone: () {}, replay: true)));

      expect(find.text('닫기'), findsOneWidget);
      expect(find.text('건너뛰기'), findsNothing);
    });

    test('세 장 문구에 시스템 이모지 글자가 없다', () {
      final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final page in kIntroPages) {
        expect(emoji.hasMatch(page.title), isFalse, reason: page.title);
        expect(emoji.hasMatch(page.body), isFalse, reason: page.body);
      }
      expect(kIntroPages, hasLength(3), reason: '세 장을 넘기지 않는다 — Epic #322');
    });
  });

  group('IntroGate', () {
    test('처음엔 안 봤고, 적으면 봤고, 지우면 다시 안 봤다', () async {
      SharedPreferences.setMockInitialValues({});
      final gate = IntroGate(preferences: await SharedPreferences.getInstance());

      expect(await gate.hasSeen(), isFalse);
      await gate.markSeen();
      expect(await gate.hasSeen(), isTrue);
      await gate.clear();
      expect(await gate.hasSeen(), isFalse);
    });

    test('키는 기기 단위다 — 사용자 id 가 안 붙는다', () {
      expect(IntroGate.key, isNot(contains(r'$')));
      expect(IntroGate.key, 'intro_seen_v1');
    });
  });
}

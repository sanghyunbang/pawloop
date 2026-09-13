// 폼 부품 한 벌 — 이슈 #445.
//
// 부품이 **약속한 형태**를 잰다: 채움 버튼 안에 진짜 FilledButton 이 있고(테스트·접근성이 그것을
// 찾는다), 눌릴 수 없으면 그라데이션이 빠지고, 입력칸에 머티리얼 아웃라인이 없고, 알약 칩이
// 선택되면 강조색이고, 시트 틀이 제목·한 줄 설명을 그린다. 화면들이 이 부품을 쓰는지는 각
// 화면의 테스트가 잰다(`schedule_screen_test` 의 "폼 부품" 묶음).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/theme/app_tokens.dart';
import 'package:heat_trip_flutter/v2/widgets/form_kit.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 320, child: child)))),
    );

void main() {
  group('PrimaryButton', () {
    testWidgets('안에 진짜 FilledButton 이 있고 라벨을 누르면 눌린다', (tester) async {
      var pressed = 0;
      await _pump(tester, PrimaryButton(label: '저장', onPressed: () => pressed++));

      expect(find.widgetWithText(FilledButton, '저장'), findsOneWidget,
          reason: '테스트와 스크린리더는 FilledButton 을 찾는다 — 그것이 있어야 한다');
      await tester.tap(find.text('저장'));
      expect(pressed, 1);
    });

    testWidgets('눌릴 수 없으면 그라데이션이 빠진다 — 회색 상자다', (tester) async {
      await _pump(tester, const PrimaryButton(label: '저장', onPressed: null));

      final box = tester.widget<DecoratedBox>(find.ancestor(
        of: find.byType(FilledButton),
        matching: find.byType(DecoratedBox),
      ).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNotNull);
    });

    testWidgets('눌릴 수 있으면 그라데이션이 있다 — 기본은 따뜻한 것', (tester) async {
      await _pump(tester, PrimaryButton(label: '저장', onPressed: () {}));

      final box = tester.widget<DecoratedBox>(find.ancestor(
        of: find.byType(FilledButton),
        matching: find.byType(DecoratedBox),
      ).first);
      expect((box.decoration as BoxDecoration).gradient, T.warm);
    });

    testWidgets('buttonKey 는 안쪽 FilledButton 에 붙는다', (tester) async {
      const key = Key('submit');
      await _pump(tester, const PrimaryButton(label: '만들기', onPressed: null, buttonKey: key));

      final button = tester.widget<FilledButton>(find.byKey(key));
      expect(button.onPressed, isNull);
    });
  });

  group('GlassField', () {
    testWidgets('머티리얼 아웃라인이 없고 흰 상자에 옅은 선이다', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await _pump(tester, GlassField(controller: c, hint: '예) 보리'));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.border, InputBorder.none,
          reason: '아웃라인이 남아 있으면 머티리얼 기본 모양이 다시 나온다');
      expect(find.text('예) 보리'), findsOneWidget);

      final box = tester.widget<Container>(find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Container),
      ).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.border!.top.color, T.line);
    });

    testWidgets('글자를 넣으면 컨트롤러에 들어간다', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await _pump(tester, GlassField(controller: c, hint: '이름'));

      await tester.enterText(find.byType(TextField), '보리');
      expect(c.text, '보리');
    });
  });

  group('PillChip', () {
    testWidgets('선택되면 강조색으로 채우고 흰 글자, 아니면 흰 반투명', (tester) async {
      await _pump(
        tester,
        Row(children: [
          PillChip(label: '병원', selected: true, onTap: () {}),
          PillChip(label: '산책', selected: false, onTap: () {}),
        ]),
      );

      BoxDecoration deco(String label) => (tester
              .widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
              .decoration as BoxDecoration);
      expect(deco('병원').color, T.accent);
      expect(deco('산책').color, isNot(T.accent));
      expect(tester.widget<Text>(find.text('병원')).style!.color, Colors.white);
    });

    testWidgets('누르면 onTap 이 온다', (tester) async {
      var taps = 0;
      await _pump(tester, PillChip(label: '병원', selected: false, onTap: () => taps++));
      await tester.tap(find.text('병원'));
      expect(taps, 1);
    });
  });

  group('PickerButton', () {
    testWidgets('값을 비울 수 있으면 × 가 있고 툴팁이 붙는다', (tester) async {
      var cleared = 0;
      await _pump(
        tester,
        PickerButton(
          icon: Icons.schedule_outlined,
          label: '오후 2:00',
          onPressed: () {},
          onClear: () => cleared++,
          clearTooltip: '시각 지우기',
        ),
      );

      await tester.tap(find.byTooltip('시각 지우기'));
      expect(cleared, 1);
    });

    testWidgets('비울 수 없으면 × 가 없다', (tester) async {
      await _pump(tester, PickerButton(icon: Icons.event_outlined, label: '9월 13일', onPressed: () {}));
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });

  group('SheetFrame', () {
    testWidgets('손잡이 · 제목 · 한 줄 설명 · 내용을 그린다', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SheetFrame(
            title: '일정 적기',
            subtitle: '9월 13일 하루만 바꿉니다',
            children: [Text('내용')],
          ),
        ),
      ));

      expect(find.text('일정 적기'), findsOneWidget);
      expect(find.text('9월 13일 하루만 바꿉니다'), findsOneWidget);
      expect(find.text('내용'), findsOneWidget);
    });

    testWidgets('설명이 없으면 그 줄이 없다', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SheetFrame(title: '크루 만들기', children: [Text('내용')])),
      ));

      expect(find.byType(Text), findsNWidgets(2), reason: '제목과 내용뿐');
    });
  });

  testWidgets('SigFab 은 접근성 이름과 툴팁이 같고 누르면 눌린다', (tester) async {
    var pressed = 0;
    await _pump(tester, SigFab(icon: Icons.add_rounded, tooltip: '일정 추가', onPressed: () => pressed++));

    await tester.tap(find.byTooltip('일정 추가'));
    expect(pressed, 1);
    expect(find.bySemanticsLabel('일정 추가'), findsOneWidget);
  });
}

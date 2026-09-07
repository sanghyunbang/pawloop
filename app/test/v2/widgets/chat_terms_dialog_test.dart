// 채팅 규칙 대화상자 — 두 줄 요약이 기본, "자세히" 로 네 줄, 1080×2400 에서 스크롤 없음 (#330).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/widgets/chat_terms_dialog.dart';

Future<bool?> _open(WidgetTester t) async {
  // 1080×2400 기기(DPR 2.625 → 411×914 논리 픽셀) — 완료 조건의 기준 화면이다.
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);

  bool? result;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await ChatTermsDialog.show(ctx),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

double _maxScroll(WidgetTester t) =>
    t.state<ScrollableState>(find.byType(Scrollable).last).position.maxScrollExtent;

void main() {
  testWidgets('기본은 두 줄 요약 — 네 글머리가 없고 스크롤이 없다', (t) async {
    await _open(t);

    expect(find.text('대화를 시작하기 전에'), findsOneWidget);
    expect(find.text(ChatTermsDialog.summary), findsOneWidget);
    expect(find.textContaining('탈퇴해도'), findsOneWidget, reason: '접힌 상태에서도 탈퇴 뒤 표시를 말한다');
    expect(find.textContaining('신고한 사실은'), findsNothing);
    expect(find.textContaining('방장은 멤버를'), findsNothing);
    expect(find.text('자세히'), findsOneWidget);
    expect(_maxScroll(t), 0, reason: '한 화면에 들어간다');
  });

  testWidgets('"자세히" 를 누르면 네 줄이 펼쳐지고, 그래도 스크롤은 없다', (t) async {
    await _open(t);

    await t.tap(find.text('자세히'));
    await t.pumpAndSettle();

    for (final line in ChatTermsDialog.details) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.textContaining('설정 > 약관 및 정책'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
    expect(_maxScroll(t), 0);
  });

  testWidgets('나중에 → false, 동의하고 시작 → true', (t) async {
    final later = _openAndTap(t, '나중에');
    expect(await later, isFalse);

    final agreed = _openAndTap(t, '동의하고 시작');
    expect(await agreed, isTrue);
  });
}

Future<bool?> _openAndTap(WidgetTester t, String button) async {
  bool? result;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await ChatTermsDialog.show(ctx),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  await t.tap(find.text(button));
  await t.pumpAndSettle();
  return result;
}

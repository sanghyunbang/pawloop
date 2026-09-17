// 채팅 규칙 대화상자 — 두 줄 요약이 기본, "자세히" 로 네 줄, 1080×2400 에서 스크롤 없음 (#330).
//
// 여기에 #682 가 붙었다: 주의 · 제재 세 줄은 **접히지 않는다.** 원스토어 검증 가이드라인이
// 채팅에 요구하는 피해 예방 문구라, "자세히" 를 누른 사람에게만 보이면 없는 것과 같다.
// 그러면서도 #330 의 완료 조건(한 화면)은 그대로 지켜야 해서 스크롤을 다시 잰다.
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

  testWidgets('주의 · 제재 세 줄은 "자세히" 를 누르기 전에 이미 보인다 (#682)', (t) async {
    await _open(t);

    expect(find.text(ChatTermsDialog.safetyTitle), findsOneWidget);
    for (final line in ChatTermsDialog.safety) {
      expect(find.text(line), findsOneWidget,
          reason: '접어 두면 읽지 않는 사람에게는 없는 문구다 — 원스토어 검증 가이드라인이 요구한다');
    }
    expect(find.text('자세히'), findsOneWidget, reason: '기능 안내 네 줄은 여전히 접혀 있다');
    expect(_maxScroll(t), 0, reason: '세 줄이 늘어도 1080×2400 한 화면에 들어간다(#330)');
  });

  testWidgets('세 줄이 각각 무엇을 말하는가 — 금전·개인정보 · 처벌 · 제재 (#682)', (t) async {
    await _open(t);

    // 문구를 바꿔도 이 셋이 사라지면 가이드라인을 못 지킨다. 그래서 통째 비교가 아니라
    // 알맹이만 본다 — 말투는 다듬어도 되지만 알맹이는 빠지면 안 된다.
    expect(find.textContaining('금전'), findsOneWidget);
    expect(find.textContaining('개인정보'), findsOneWidget);
    expect(find.textContaining('신고해 주세요'), findsOneWidget);

    expect(find.textContaining('불법 촬영물'), findsOneWidget);
    expect(find.textContaining('처벌될 수 있습니다'), findsOneWidget);

    expect(find.textContaining('계정이 정지·해지'), findsOneWidget);
  });

  testWidgets('제재 문구가 약관보다 세지 않다 — 삭제·비노출 · 이용 제한 · 정지·해지까지 (#682)', (t) async {
    await _open(t);

    // 이용약관 제7조 3항(삭제·비노출) · 제9조 1항(이용 정지 또는 해지) 이 우리가 할 수 있다고
    // 적어 둔 전부다. 여기에 없는 제재(법적 고발 · 영구 차단 등)를 안내에 적으면 약관과 어긋난다.
    final sanction = ChatTermsDialog.safety.last;
    expect(sanction, contains('삭제·비노출'));
    expect(sanction, contains('이용이 제한'));
    expect(sanction, contains('계정이 정지·해지'));
  });

  testWidgets('다시 보기는 동의를 다시 받지 않는다 — "닫기" 하나, 네 줄은 펼친 채 (#682)', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => ChatTermsDialog.showAgain(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('채팅 이용 안내'), findsOneWidget);
    expect(find.text('동의하고 시작'), findsNothing,
        reason: '이미 동의한 사람에게 또 내밀면 무엇에 동의하는 것인지 모호해진다');
    expect(find.text('나중에'), findsNothing);
    expect(find.text('닫기'), findsOneWidget);

    for (final line in ChatTermsDialog.safety) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text(ChatTermsDialog.details.first), findsOneWidget,
        reason: '찾으러 온 사람 앞에서 또 접어 두지 않는다');
    expect(_maxScroll(t), 0, reason: '펼친 채로도 한 화면에 들어간다');

    await t.tap(find.text('닫기'));
    await t.pumpAndSettle();
    expect(find.text('채팅 이용 안내'), findsNothing);
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

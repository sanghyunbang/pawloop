// 약관 화면에 마크다운 별표가 안 보인다 — 이슈 #550.
//
// ## 무엇이 있었나
//
// 문서는 `assets/terms/*.md` 인데 화면은 그대로 글자로 그렸다. 그래서 약관 본문에
// `별도의 **위치기반서비스 이용약관**에서 정합니다` 처럼 별표가 그대로 보였다. 네 문서에서
// 마흔한 줄이었다.
//
// **이 화면은 심사에서 열린다.** 애플·구글 심사자가 보는 것이 정확히 이 화면이고, 사용자도
// 문제가 생겼을 때 여기를 읽는다.
//
// ## 여기서 재는 것
//
// 1. 장치가 `**…**` 를 굵은 조각으로 가른다(값으로).
// 2. **진짜 문서 넷**을 읽어 남은 별표가 없는지 본다 — 짝이 안 맞는 `**` 가 새로 들어오면
//    여기서 빨간불이다. 장치만 재면 문서가 낡아도 초록이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:heat_trip_flutter/v2/screens/settings/legal_document_screen.dart';

/// 조각들을 이어 붙인 글자 — 화면에 보이는 것이 이것이다.
String _rendered(List<TextSpan> spans) => spans.map((s) => s.text ?? '').join();

/// 굵게 그려지는 조각들.
List<String> _bolds(List<TextSpan> spans) => [
      for (final s in spans)
        if (s.style?.fontWeight == FontWeight.w800) s.text ?? '',
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('장치 — 굵게만 해석한다', () {
    test('별표는 사라지고 그 안이 굵어진다', () {
      final spans = boldSpans('별도의 **위치기반서비스 이용약관**에서 정합니다.');

      expect(_rendered(spans), '별도의 위치기반서비스 이용약관에서 정합니다.');
      expect(_bolds(spans), ['위치기반서비스 이용약관']);
    });

    test('한 줄에 여럿도 가른다', () {
      final spans = boldSpans('**만 14세 미만**은 **가입할 수 없습니다**.');

      expect(_rendered(spans), '만 14세 미만은 가입할 수 없습니다.');
      expect(_bolds(spans), ['만 14세 미만', '가입할 수 없습니다']);
    });

    test('강조가 없는 글은 조각 하나 그대로다', () {
      final spans = boldSpans('제1조(목적)\n본 약관은 …');

      expect(_rendered(spans), '제1조(목적)\n본 약관은 …');
      expect(_bolds(spans), isEmpty);
    });

    test('짝이 없는 별표는 그대로 둔다 — 지우면 문서가 조용히 달라진다', () {
      final spans = boldSpans('여는 **것만 있다');

      expect(_rendered(spans), '여는 **것만 있다');
      expect(_bolds(spans), isEmpty);
    });

    test('목록 표시는 안 건드린다 — 글머리표로 읽힌다', () {
      final spans = boldSpans('- 수집 항목\n- 보유 기간');

      expect(_rendered(spans), '- 수집 항목\n- 보유 기간');
    });

    test('빈 강조(****)는 강조가 아니다', () {
      final spans = boldSpans('가****나');

      expect(_rendered(spans), '가****나');
      expect(_bolds(spans), isEmpty);
    });
  });

  group('진짜 문서 넷 — 남은 별표가 없다 (#550)', () {
    for (final doc in LegalDocument.values) {
      test('${doc.title} 에 ** 가 안 보인다', () async {
        final source = await rootBundle.loadString(doc.assetPath);

        final shown = _rendered(boldSpans(source));

        expect(shown.contains('**'), isFalse,
            reason: '''
${doc.assetPath} 에 짝이 안 맞는 `**` 가 있습니다. 약관 본문에 정리 안 된 기호가 보이면
문서 자체의 신뢰가 깎입니다 — 이 화면은 심사자가 여는 자리입니다 (#550).''');
        expect(shown.replaceAll('**', ''), source.replaceAll('**', ''),
            reason: '별표 말고는 한 글자도 안 바뀌어야 합니다 — 약관은 글자가 곧 내용입니다');
      });
    }
  });

  // ── 화면이 실제로 그 장치를 쓰는가 ──────────────────────────────────
  //
  // 장치만 재면 **화면이 예전처럼 글자 그대로 그려도 전부 초록**이다. 실제로 그랬다 —
  // `SelectableText.rich(TextSpan(text: _body))` 로 되돌리는 변형이 아무 테스트도 안 깼다.
  testWidgets('약관 화면에 별표가 안 보인다 — 장치가 물려 있다 (#550)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: LegalDocumentScreen(document: LegalDocument.terms),
    ));
    // `pumpAndSettle` 은 여기서 시간 초과다 — 문서를 읽는 동안 도는 스피너가 영원히
    // 프레임을 부른다. 그리고 `rootBundle` 읽기는 **진짜 비동기**라 `pump` 의 가짜 시간으로는
    // 안 끝난다 — `runAsync` 안에서 실제로 기다린다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: '문서를 못 읽었다');

    final shown = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
        .join();

    expect(shown, contains('위치기반서비스 이용약관'), reason: '본문이 그려졌는지 먼저 본다');
    expect(shown.contains('**'), isFalse,
        reason: '심사자가 여는 화면이다 — 약관 본문에 정리 안 된 기호가 있으면 안 된다');
    expect(shown, contains('제1조(목적)'));
  });

  test('강조가 실제로 문서에 있다 — 아무것도 안 바뀌는 검사는 늘 초록이다', () async {
    var bolded = 0;
    for (final doc in LegalDocument.values) {
      bolded += _bolds(boldSpans(await rootBundle.loadString(doc.assetPath))).length;
    }

    expect(bolded, greaterThan(30),
        reason: '네 문서에 굵게가 마흔 곳쯤 있습니다. 한 자릿수면 장치나 경로가 깨진 것입니다 — '
            '지금 센 것: $bolded');
  });
}

// 로그인 **전에** 받는 약관 동의 — 애플 App Review Guideline 1.2.
//
// 1.2 는 UGC 앱에 "가입·로그인 전에 이용약관에 동의를 받으라" 고 요구하고, App Store 심사가 그
// 조건으로 반려했다. 우리 동의 화면(`consent_screen.dart`)은 소셜 로그인으로 계정이 생긴 **뒤에** 뜬다.
// 그래서 로그인 화면의 소셜 버튼 위에 체크칸 하나를 두고, 체크해야 세 버튼이 켜진다.
//
// 여기서 재는 것:
//  1. 체크 전에는 세 버튼 어느 것도 로그인 왕복을 시작하지 않는다 — 그리고 무엇이 모자란지 말한다.
//  2. 체크하면 켜진다. "그냥 둘러보기" 는 처음부터 켜져 있다(가입이 아니다).
//  3. 두 문서 이름이 링크고, 동의 화면이 쓰는 같은 전문 화면을 연다.
//  4. 한 번 동의한 기기는 체크된 채로 뜬다 — **문서 버전이 같을 때만.**
//  5. 체크칸이 들어와도 작은 폰 · 큰 글자에서 넘치지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/login_terms_gate.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/screens/settings/legal_document_screen.dart';

const _kakao = '카카오로 시작하기';
const _google = 'Google로 시작하기';
const _apple = 'Apple로 계속하기';

/// 왕복을 시작했는지 센다. 시작했으면 서버 오류로 돌려보내 화면이 살아 있게 한다.
List<String> _recordRoundTrips() {
  final urls = <String>[];
  SocialLoginService.authenticator = ({required url, required callbackUrlScheme, required options}) async {
    urls.add(url);
    return 'pawloop://login-callback?error=test_only';
  };
  return urls;
}

Future<LoginTermsGate> _gate(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  return LoginTermsGate(preferences: await SharedPreferences.getInstance());
}

Future<void> _pump(WidgetTester tester, LoginTermsGate gate) async {
  await tester.pumpWidget(MaterialApp(home: LoginScreen(showAppleSignIn: true, termsGate: gate)));
  await tester.pumpAndSettle();
}

/// 전문 화면은 asset 을 **진짜 비동기**로 읽는다 — 그동안 스피너가 돌아 `pumpAndSettle` 이 끝나지 않는다.
/// 전환 애니메이션만 가짜 시간으로 밀고, 읽기는 `runAsync` 안에서 실제로 기다린다
/// (`legal_document_markdown_test.dart` 와 같은 방법).
Future<void> _waitForDocument(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

/// 전문 화면에 그려진 글자 전부.
String _shownDocument(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
    .join();

Future<void> _check(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('login-terms-check')));
  await tester.pump();
}

void main() {
  tearDown(() {
    SocialLoginService.resetForTest();
    AuthState.resetForTest();
  });

  // ─────────────────── 1 · 2. 체크해야 켜진다 ───────────────────

  testWidgets('체크 전에는 세 버튼 어느 것도 로그인을 시작하지 않고, 무엇이 모자란지 말한다', (tester) async {
    final urls = _recordRoundTrips();
    await _pump(tester, await _gate({}));

    expect(find.text('이용약관과 개인정보처리방침에 동의합니다', findRichText: true), findsOneWidget);

    for (final label in [_kakao, _google, _apple]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(urls, isEmpty, reason: '''
애플 지침 1.2 — 약관 동의가 가입·로그인보다 먼저다. 버튼이 왕복을 시작하면 동의 전에 계정이 생긴다.''');
    expect(AuthState.status.value, isNot(AuthStatus.authenticating));
    expect(find.text(loginTermsRequiredMessage), findsOneWidget,
        reason: '흐린 버튼을 눌렀는데 아무 일도 없으면 앱이 고장 난 줄 안다');
  });

  testWidgets('체크하면 켜지고, 누르면 그 공급자로 왕복을 시작한다', (tester) async {
    final urls = _recordRoundTrips();
    await _pump(tester, await _gate({}));

    await _check(tester);
    await tester.tap(find.text(_kakao));
    await tester.pumpAndSettle();

    expect(urls, hasLength(1));
    expect(Uri.parse(urls.single).path, endsWith('/oauth2/authorization/kakao'));
  });

  testWidgets('체크를 다시 풀면 도로 꺼진다', (tester) async {
    final urls = _recordRoundTrips();
    await _pump(tester, await _gate({}));

    await _check(tester);
    await _check(tester);
    await tester.tap(find.text(_google));
    await tester.pumpAndSettle();

    expect(urls, isEmpty);
  });

  testWidgets('"그냥 둘러보기" 는 체크 없이 눌린다 — 가입이 아니다', (tester) async {
    final gate = await _gate({});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LoginScreen(showAppleSignIn: true, termsGate: gate))),
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('그냥 둘러보기'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing,
        reason: '둘러보기는 계정을 만들지 않는다 — 약관 체크로 막을 이유가 없다');
  });

  // ─────────────────── 3. 문서 링크 ───────────────────

  testWidgets('"이용약관" 과 "개인정보처리방침" 이 링크고, 동의 화면과 같은 전문 화면을 연다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, await _gate({}));

    await tester.tapOnText(find.textRange.ofSubstring('이용약관'));
    await _waitForDocument(tester);
    expect(tester.widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen)).document, LegalDocument.terms,
        reason: '원문은 asset 하나다(#165) — 다른 화면을 만들면 어느 쪽이 계약인지 말할 수 없다');
    expect(_shownDocument(tester), contains('일절 허용하지 않습니다'),
        reason: '링크로 연 전문에 제6조의 무관용 조항이 있다 — 체크하는 사람이 읽을 수 있어야 한다');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('개인정보처리방침'));
    await _waitForDocument(tester);
    expect(tester.widget<LegalDocumentScreen>(find.byType(LegalDocumentScreen)).document, LegalDocument.privacy);
  });

  testWidgets('링크를 눌러도 체크는 안 바뀐다 — 읽는 것과 동의하는 것은 다른 동작이다', (tester) async {
    final urls = _recordRoundTrips();
    await _pump(tester, await _gate({}));

    await tester.tapOnText(find.textRange.ofSubstring('이용약관'));
    await _waitForDocument(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(_kakao));
    await tester.pumpAndSettle();

    expect(urls, isEmpty);
  });

  // ─────────────────── 4. 기기가 기억한다 — 버전과 함께 ───────────────────

  testWidgets('체크하고 로그인을 누르면 이 기기에 지금 문서 버전과 함께 남는다', (tester) async {
    _recordRoundTrips();
    final gate = await _gate({});
    await _pump(tester, gate);

    await _check(tester);
    await tester.tap(find.text(_kakao));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LoginTermsGate.key),
        'TERMS:${LegalDocument.terms.version}|PRIVACY:${LegalDocument.privacy.version}');
  });

  testWidgets('같은 버전에 동의했던 기기는 체크된 채로 뜬다 — 바로 누를 수 있다', (tester) async {
    final urls = _recordRoundTrips();
    await _pump(tester, await _gate({LoginTermsGate.key: LoginTermsGate.currentStamp}));

    await tester.tap(find.text(_kakao));
    await tester.pumpAndSettle();

    expect(urls, hasLength(1));
  });

  testWidgets('약관 버전이 바뀌었으면 다시 체크해야 한다 — 옛 동의가 새 약관에 이어지지 않는다', (tester) async {
    final urls = _recordRoundTrips();
    // 지금 버전보다 앞선 이용약관에 동의했던 기기.
    await _pump(tester, await _gate({LoginTermsGate.key: 'TERMS:v0.9|PRIVACY:${LegalDocument.privacy.version}'}));

    await tester.tap(find.text(_kakao));
    await tester.pumpAndSettle();

    expect(urls, isEmpty, reason: '바뀐 약관에 옛 체크가 이어지면 그것은 동의가 아니다');
  });

  testWidgets('체크를 풀면 기억도 지운다 — 다음에 켜져 있으면 마지막 뜻과 다르다', (tester) async {
    await _pump(tester, await _gate({LoginTermsGate.key: LoginTermsGate.currentStamp}));

    await _check(tester);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LoginTermsGate.key), isNull);
  });

  test('저장된 값을 못 읽으면 동의하지 않은 것으로 본다 — 실패를 "했다" 로 읽으면 동의 없이 버튼이 켜진다', () async {
    // 문자열 자리에 숫자가 들어 있으면 getString 이 던진다 — 읽기 실패를 그렇게 만든다.
    final gate = await _gate({LoginTermsGate.key: 12});
    expect(await gate.hasAgreed(), isFalse);
  });

  // ─────────────────── 5. 넘치지 않는다 ───────────────────

  // 글자 배율은 1.3 까지다. 1.5 에서는 **이 PR 과 무관하게** "Google로 시작하기" 줄이 360dp 에서 옆으로
  // 넘친다(버튼 글자에 Flexible 이 없다 — 테스트 글꼴 기준, 실제 Pretendard 는 라틴 글자가 그 절반쯤이다).
  // 여기서 재려는 것은 체크칸이 더한 **세로**다.
  for (final (label, size, scale) in [
    ('작은 폰(320×568)', const Size(320, 568), 1.0),
    ('보통 폰(360×740) · 글자 1.3배', const Size(360, 740), 1.3),
    ('기본 창(800×600) · 이유 알약', const Size(800, 600), 1.0),
  ]) {
    testWidgets('체크칸이 들어와도 $label 에서 넘치지 않고, 버튼까지 스크롤로 닿는다', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final urls = _recordRoundTrips();
      final gate = await _gate({});

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: LoginScreen(showAppleSignIn: true, reason: '로그인하면 산책을 기록할 수 있어요', termsGate: gate),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '노란 줄무늬 — 체크칸과 이유 알약이 함께 서면 세로가 모자랐다');

      await tester.ensureVisible(find.byKey(const Key('login-terms-check')));
      await _check(tester);
      await tester.ensureVisible(find.text(_apple));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_apple));
      await tester.pumpAndSettle();

      expect(urls, hasLength(1), reason: '맨 아래 버튼까지 닿아야 한다 — 넘친 자리는 눌리지 않는다');
    });
  }
}

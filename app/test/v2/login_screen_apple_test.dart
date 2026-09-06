// 로그인 화면의 Apple 버튼 — 이슈 #301 (App Store 심사 지침 4.8).
//
// 버튼은 iOS 에서만 기본으로 보인다. 지침이 iOS 앱에 적용되고, 안드로이드 사용자에게 Apple
// 계정을 권할 이유가 없다. 여기서는 플래그로 켜고 끄며, 플랫폼 기본값은 `debugDefaultTargetPlatformOverride`
// 로 잰다. HIG 규격(검정 배경 · 흰 글자 · 승인된 문구)은 구글 버튼처럼 회귀로 잠근다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';

void main() {
  const appleLabel = 'Apple로 계속하기';

  BoxDecoration decorationOf(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SocialLoginService.resetForTest();
    AuthState.resetForTest();
  });

  testWidgets('플래그를 켜면 Apple 버튼이 카카오·구글 아래에 보인다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen(showAppleSignIn: true)));
    await tester.pump();

    expect(find.text(appleLabel), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('Google로 시작하기'), findsOneWidget);
  });

  testWidgets('플래그를 끄면 없다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen(showAppleSignIn: false)));
    await tester.pump();

    expect(find.text(appleLabel), findsNothing);
    expect(find.byIcon(Icons.apple), findsNothing);
  });

  // 플랫폼 오버라이드는 **테스트 본문 안에서** 되돌린다 — 테스트 프레임워크가 본문이 끝난 직후
  // (tearDown 보다 먼저) 이 변수가 원래대로인지 검사한다(실측: tearDown 에서 되돌리면 빨강).
  // 같은 const 위젯을 다시 pump 하면 재빌드가 안 되므로 플랫폼마다 테스트를 따로 둔다.
  testWidgets('플래그가 없으면 안드로이드에서는 없다 — 지침은 iOS 앱에 적용된다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();
      expect(find.text(appleLabel), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('플래그가 없으면 iOS 에서는 보인다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();
      expect(find.text(appleLabel), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('HIG 규격 — 검정 배경, 흰 글자, 승인된 문구', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen(showAppleSignIn: true)));
    await tester.pump();

    final decoration = decorationOf(tester, appleLabel);
    expect(decoration.color, const Color(0xFF000000));

    final label = tester.widget<Text>(find.text(appleLabel));
    expect(label.style!.color, const Color(0xFFFFFFFF));
    expect(appleLabel, isIn(['Apple로 로그인', 'Apple로 가입하기', 'Apple로 계속하기']),
        reason: 'HIG 가 허용하는 문구 셋 중 하나여야 한다');
  });

  testWidgets('누르면 카카오·구글과 같은 왕복을 apple 로 시작한다', (tester) async {
    String? seenUrl;
    SocialLoginService.authenticator = ({required url, required callbackUrlScheme}) async {
      seenUrl = url;
      return 'heattrip://login-callback?error=apple_not_configured';
    };

    await tester.pumpWidget(const MaterialApp(home: LoginScreen(showAppleSignIn: true)));
    await tester.tap(find.text(appleLabel));
    await tester.pumpAndSettle();

    expect(Uri.parse(seenUrl!).path, endsWith('/oauth2/authorization/apple'));
    expect(Uri.parse(seenUrl!).queryParameters['state'], isNotEmpty);
    // 키가 없는 서버의 답 — 서버 오류 문구로 안내되고 화면은 살아 있다.
    expect(find.text('로그인 서버에 문제가 있어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(AuthState.status.value, isNot(AuthStatus.authenticating));
  });
}

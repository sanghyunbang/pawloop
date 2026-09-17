// 로그인 화면 위젯 테스트 — 어떤 소셜 버튼이 떠 있는가.
//
// HeatTrip(app/lib/main.dart)을 통째로 pump 하면 라우터·Provider·네이버 지도 SDK
// 초기화까지 딸려온다. 이 테스트가 보려는 것은 로그인 화면 하나뿐이라
// MaterialApp(home: LoginScreen()) 만 띄운다.
// (예전에는 Env.apiBase 가 dotenv 초기화를 요구해서 아예 불가능했다. → 이슈 #29)
//
// 픽셀 위치는 보지 않는다(이슈 #21). 다만 구글 버튼의 색은 예외다 —
// 브랜드 가이드가 "임의 색상 변경 금지"를 요구하므로 회귀로 잠근다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';

/// 주어진 에셋 경로를 그리는 [SvgPicture] 를 찾는 Finder.
Finder svgAsset(String assetName) => find.byWidgetPredicate(
      (w) =>
          w is SvgPicture &&
          w.bytesLoader is SvgAssetLoader &&
          (w.bytesLoader as SvgAssetLoader).assetName == assetName,
      description: 'SvgPicture($assetName)',
    );

void main() {
  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
  }

  group('LoginScreen 소셜 버튼 구성', () {
    testWidgets('카카오와 구글 버튼이 하나씩 보이고 네이버 버튼은 보이지 않는다', (tester) async {
      await pumpLoginScreen(tester);

      expect(find.text('카카오로 시작하기'), findsOneWidget);
      expect(find.text('Google로 시작하기'), findsOneWidget);
      expect(find.text('네이버로 시작하기'), findsNothing);
    });

    testWidgets('구글 로고 에셋을 쓰고 네이버 로고 에셋은 쓰지 않는다', (tester) async {
      await pumpLoginScreen(tester);

      expect(svgAsset('assets/icons/google.svg'), findsOneWidget);
      expect(svgAsset('assets/icons/kakao.svg'), findsOneWidget);
      expect(svgAsset('assets/icons/naver.svg'), findsNothing);
    });
  });

  group('구글 버튼 브랜드 가이드 준수', () {
    /// 라벨 Text 를 감싸는 버튼 Container 의 decoration.
    BoxDecoration decorationOf(WidgetTester tester, String label) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('배경이 흰색이고 테두리가 있다', (tester) async {
      await pumpLoginScreen(tester);

      final decoration = decorationOf(tester, 'Google로 시작하기');

      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(decoration.border, isNotNull);
    });

    testWidgets('라벨 텍스트가 검정 계열이다', (tester) async {
      await pumpLoginScreen(tester);

      final label = tester.widget<Text>(find.text('Google로 시작하기'));
      final color = label.style!.color!;

      expect(color.a, 1.0, reason: '라벨이 반투명하면 안 된다');
      expect(
        color.computeLuminance(),
        lessThan(0.1),
        reason: '구글 버튼 라벨은 검정 계열이어야 한다 — 임의 색상 변경 금지',
      );
    });

    testWidgets('카카오 버튼은 노란 배경에 테두리가 없다 — 구글 스타일이 번지지 않는다', (tester) async {
      await pumpLoginScreen(tester);

      final decoration = decorationOf(tester, '카카오로 시작하기');

      expect(decoration.color, const Color(0xFFFEE500));
      expect(decoration.border, isNull);
    });
  });

  // ── 실패 사유별 안내 문구 (이슈 #12 완료 조건 9) ──────────────────────────
  //
  // 예전에는 취소·네트워크·서버 오류가 전부 "로그인에 실패했어요. 다시 시도해 주세요."
  // 한 줄이었다. 스스로 창을 닫은 사람에게 "실패" 라고 말하면 앱이 고장 난 줄 알고,
  // 비행기 모드인 사람에게 "다시 시도" 라고 말하면 될 때까지 누른다.
  //
  // `FlutterWebAuth2.authenticate` 는 플랫폼 채널이라 테스트에서 부를 수 없다.
  // `SocialLoginService.authenticator` 를 갈아끼워 세 갈래를 만든다.
  group('로그인 실패 사유별 안내', () {
    tearDown(() {
      SocialLoginService.resetForTest();
      AuthState.resetForTest();
    });

    /// [onAuthenticate] 가 던지거나 돌려주는 것으로 실패를 흉내 낸다.
    Future<void> tapKakao(
      WidgetTester tester,
      Future<String> Function() onAuthenticate,
    ) async {
      SocialLoginService.authenticator =
          ({required url, required callbackUrlScheme, required options}) => onAuthenticate();

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('카카오로 시작하기'));
      await tester.pumpAndSettle();
    }

    testWidgets('사용자가 취소하면 "취소" 라고 말한다 — 실패라고 하지 않는다', (tester) async {
      await tapKakao(
        tester,
        () => throw PlatformException(code: 'CANCELED'),
      );

      expect(find.text('로그인을 취소했어요.'), findsOneWidget);
      expect(find.textContaining('실패'), findsNothing);
    });

    testWidgets('네트워크 오류는 연결 상태를 확인하라고 말한다', (tester) async {
      await tapKakao(
        tester,
        () => throw const SocketException('no route to host'),
      );

      expect(
        find.text('네트워크에 연결할 수 없어요. 연결 상태를 확인해 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('서버 오류는 잠시 후 다시 시도하라고 말한다', (tester) async {
      // 계약과 다른 콜백(토큰 없음) — 사용자 탓이 아니라 서버 탓이다.
      await tapKakao(
        tester,
        () async => 'pawloop://login-callback?error=account_state_invalid',
      );

      expect(
        find.text('로그인 서버에 문제가 있어요. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('세 문구가 서로 다르다 — 한 문장으로 뭉개지지 않는다', (tester) async {
      final messages = {
        loginFailureMessage(SocialLoginOutcome.canceled),
        loginFailureMessage(SocialLoginOutcome.networkError),
        loginFailureMessage(SocialLoginOutcome.serverError),
      };

      expect(messages.length, 3);
    });

    testWidgets('타임아웃도 네트워크 오류로 분류된다', (tester) async {
      await tapKakao(tester, () => throw TimeoutException('slow'));

      expect(
        find.text('네트워크에 연결할 수 없어요. 연결 상태를 확인해 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('실패해도 authenticating 에 머물지 않는다', (tester) async {
      await tapKakao(tester, () => throw PlatformException(code: 'CANCELED'));

      expect(AuthState.status.value, isNot(AuthStatus.authenticating));
    });
  });
}

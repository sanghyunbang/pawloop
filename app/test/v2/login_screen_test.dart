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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';

/// 소셜 버튼은 약관 체크칸을 눌러야 켜진다(애플 지침 1.2 — `login_terms_test.dart`). 버튼을 누르는
/// 검사는 먼저 체크한다. 문장 가운데는 링크라 동그라미를 누른다.
Future<void> agreeToTerms(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('login-terms-check')));
  await tester.pump();
}

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
      await agreeToTerms(tester);
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

  // ── 왕복의 결과는 이 화면의 생존에 걸려 있지 않다 (이슈 #673 ㄷ) ──────────────
  //
  // 이 화면은 `/home` 위에 `Navigator.push` 로 얹혀 열릴 때가 있다(나 탭 · 오늘의 케어
  // 카드). 그 아래의 `/home` 페이지가 갈아 끼워지면 **얹힌 이 화면도 함께 제거된다**
  // (Flutter `navigator.dart:1606`). 예전에는 왕복이 끝나고 돌아온 자리가
  // `if (!mounted) return;` 이라, 그때 성공한 로그인이 `completeLogin` 에 닿지 못했다.
  // 실패도 `cancelAuthenticating` 에 닿지 못해 상태가 `authenticating` 에 멈췄는데,
  // 그 상태에서 `authRedirect` 는 어디로도 안 보내므로 앱이 그 자리에 굳는다.
  //
  // #673 의 ㄱ·ㄴ 을 고치면 화면이 안 사라지지만, **여기가 화면에 기대고 있다는 사실
  // 자체**는 그대로다. 화면을 떼고 왕복을 끝내 본다.
  group('화면이 사라져도 왕복은 제 결과를 남긴다 (#673)', () {
    tearDown(() {
      SocialLoginService.resetForTest();
      AuthState.resetForTest();
    });

    /// 왕복을 붙잡아 둔다. [gate] 를 열어야 콜백이 돌아온다.
    void gatedAuthenticator(Completer<void> gate, {required bool ok}) {
      SocialLoginService.authenticator =
          ({required url, required callbackUrlScheme, required options}) async {
        final state = Uri.parse(url).queryParameters['state'] ?? '';
        await gate.future;
        if (!ok) throw PlatformException(code: 'CANCELED');
        return 'pawloop://login-callback?code=CODE-673&state=$state';
      };
    }

    /// 로그인 화면을 띄우고 카카오를 누른 뒤, **그 화면을 트리에서 뺀다.**
    Future<void> tapThenRemoveScreen(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await agreeToTerms(tester);
      await tester.tap(find.text('카카오로 시작하기'));
      await tester.pump();
      expect(AuthState.status.value, AuthStatus.authenticating);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump();
      expect(find.byType(LoginScreen), findsNothing);
    }

    testWidgets('성공은 화면 없이도 completeLogin 까지 간다', (tester) async {
      SocialLoginService.tokenStore = _MemoryTokenStore();
      SocialLoginService.exchanger =
          ({required provider, required code, required state}) async =>
              const AuthTokens(accessToken: 'AT-673', refreshToken: 'RT-673', expiresIn: 3600);
      AuthState.configureForTest(
        tokenStore: _MemoryTokenStore(access: 'AT-673'),
        repository: AuthRepositoryImpl(
          baseUrl: 'https://api.example.test',
          plainClient: MockClient((_) async => _meResponse()),
          authedClient: AuthedClient(
            inner: MockClient((_) async => _meResponse()),
            baseUrl: 'https://api.example.test',
            store: _MemoryTokenStore(access: 'AT-673'),
          ),
        ),
      );
      final gate = Completer<void>();
      gatedAuthenticator(gate, ok: true);

      await tapThenRemoveScreen(tester);
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        AuthState.status.value,
        AuthStatus.authenticated,
        reason: '토큰은 받았는데 상태가 안 올라가면 라우터가 화면을 옮길 이유가 없다',
      );
      expect(AuthState.user!.id, 7);
    });

    testWidgets('실패도 화면 없이 authenticating 을 되돌린다 — 안 그러면 앱이 굳는다', (tester) async {
      SocialLoginService.tokenStore = _MemoryTokenStore();
      final gate = Completer<void>();
      gatedAuthenticator(gate, ok: false);

      await tapThenRemoveScreen(tester);
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        AuthState.status.value,
        isNot(AuthStatus.authenticating),
        reason: 'authenticating 에 멈추면 authRedirect 가 어디로도 안 보낸다',
      );
    });
  });
}

/// 메모리 위의 토큰 저장소 — 실저장소는 플랫폼 채널이라 테스트에서 던진다(정책 #21).
class _MemoryTokenStore implements AuthTokenStore {
  String? access;
  String? refresh;

  _MemoryTokenStore({this.access});

  @override
  Future<String?> readAccessToken() async => access;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
  }
  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

/// `GET /auth/me` 의 200 본문. 한글이 있으므로 charset 을 밝힌다.
http.Response _meResponse() => http.Response(
      jsonEncode({'id': 7, 'nickname': '보리아빠', 'provider': 'kakao'}),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

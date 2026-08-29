// 로그인 화면 위젯 테스트 — 어떤 소셜 버튼이 떠 있는가.
//
// HeatTrip(app/lib/main.dart)을 통째로 pump 하면 Env.apiBase 가 dotenv 를 요구해
// 초기화 예외가 난다. 그래서 MaterialApp(home: LoginScreen()) 만 띄운다.
//
// 픽셀 위치는 보지 않는다(이슈 #21). 다만 구글 버튼의 색은 예외다 —
// 브랜드 가이드가 "임의 색상 변경 금지"를 요구하므로 회귀로 잠근다.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

// 홈이 **기기 글자 크기**를 키워도 안 넘치는가 — 이슈 #396.
//
// ## 왜 이 테스트가 없으면 안 잡히나
//
// 위젯 테스트의 기본 창은 **800x600 · 1.0배**다. 어떤 폰보다 넓고, 글자는 아무도 안 키운
// 상태다. 그래서 폭 때문에 나는 넘침도, 글자 배율 때문에 나는 넘침도 **여기 있는 어떤
// 테스트에도 안 걸린다.** 폭과 배율을 **함께** 걸어야 한다(#386 에서 배운 것이다).
//
// ## 어디까지 재는가
//
//  - **360dp** — 갤럭시 S8·A 다수의 폭. 우리가 가진 가장 좁은 실기기다.
//  - **1.5배** — 접근성 설정이 아니라 삼성 One UI 의 **글자 크기 슬라이더**로 닿는 값이다.
//    노안·저시력 사용자에게는 기본에 가깝다.
//  - **2.0배** — 접근성 설정의 위쪽. 여기서도 넘치지 않아야 하고, 안 들어가면 **스크롤로**
//    받는다. 잘라내지 않는다 — 잘리면 "급할 때 · 가까운 동물병원" 이 화면 밖으로 나간다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

/// 논리 폭 [widthDp] 의 화면으로 바꾼다 — 물리 픽셀이 아니라 **dp** 로 적는다.
void useWidth(WidgetTester tester, double widthDp, {double heightDp = 780}) {
  const ratio = 3.0;
  tester.view.physicalSize = Size(widthDp * ratio, heightDp * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
}

Widget _home({double textScale = 1.0}) => MaterialApp(
      home: Builder(
        // 화면 크기는 view 에서 온 것을 그대로 두고 글자 배율만 바꾼다 — MediaQueryData 를
        // 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const TodayScreen(),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, {required double width, required double scale}) async {
  useWidth(tester, width);
  await tester.pumpWidget(_home(textScale: scale));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
    AuthState.resetForTest();
    // 게스트로 둔다 — 서버를 안 부르고 홈이 온전히 그려진다.
    AuthState.status.value = AuthStatus.unauthenticated;
  });
  tearDown(AuthState.resetForTest);

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('360dp · 글자 $scale배에서 홈이 안 넘친다', (tester) async {
      await _pump(tester, width: 360, scale: scale);

      expect(tester.takeException(), isNull,
          reason: '1.5배는 삼성 One UI 의 슬라이더로 닿는 값이다 — 접근성 설정까지 안 가도 된다');
    });
  }

  testWidgets('393dp · 글자 2.0배에서도 안 넘친다', (tester) async {
    await _pump(tester, width: 393, scale: 2.0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('안 들어가면 스크롤로 받는다 — 잘라내지 않는다', (tester) async {
    await _pump(tester, width: 360, scale: 2.0);

    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets, reason: '스크롤이 없으면 아래 카드가 화면 밖으로 나간다');

    // 실제로 밀린다 — 스크롤 위젯만 있고 안 움직이면 잘라낸 것과 같다.
    await tester.drag(find.byType(TodayScreen), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('글자를 키워도 "급할 때" 는 화면 안에 남는다 — 아플 때 닿아야 하는 자리다', (tester) async {
    await _pump(tester, width: 360, scale: 2.0);

    final emergency = find.text('급할 때 · 가까운 동물병원');
    expect(emergency, findsOneWidget);

    // 화면 밖으로 밀려 있으면 스크롤해서 데려온다. 데려올 수 없으면 실패한다.
    await tester.scrollUntilVisible(emergency, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    final box = tester.getRect(emergency);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(box.bottom, lessThanOrEqualTo(screen),
        reason: '전화까지 두 번 만에 닿아야 하는 자리다(#337) — 화면 밖이면 없는 것과 같다');
  });

  testWidgets('글자를 키우면 버튼 둘이 위아래로 선다 — 이름이 안 잘린다', (tester) async {
    await _pump(tester, width: 360, scale: 1.5);

    // 나란히 두면 좁은 쪽이 안 들어가 "코스 …" 가 된다. 무엇을 누르는지 알 수 없다.
    expect(find.text('산책 시작'), findsOneWidget);
    expect(find.text('코스 찾기'), findsOneWidget);

    final walk = tester.getRect(find.text('산책 시작'));
    final course = tester.getRect(find.text('코스 찾기'));
    expect(course.top, greaterThan(walk.bottom),
        reason: '위아래로 서야 폭이 두 배가 되어 온전한 이름이 들어간다');
  });

  testWidgets('1.0배에서는 버튼 둘이 나란하다 — 평소 화면을 바꾸지 않는다', (tester) async {
    await _pump(tester, width: 360, scale: 1.0);

    final walk = tester.getRect(find.text('산책 시작'));
    final course = tester.getRect(find.text('코스 찾기'));
    expect(course.left, greaterThan(walk.right));
  });

  testWidgets('1.0배에서는 지금 모양 그대로다 — 고치면서 평소 화면을 바꾸지 않는다', (tester) async {
    await _pump(tester, width: 360, scale: 1.0);

    expect(tester.takeException(), isNull);
    expect(find.text('아직 등록된 아이가 없어요'), findsOneWidget);
    expect(find.text('급할 때 · 가까운 동물병원'), findsOneWidget);
    expect(find.text('산책 시작'), findsOneWidget);
  });

  group('하단 탭', () {
    // 탭은 홈 안이 아니라 셸에 산다 — 홈만 재면 여기 넘침을 못 본다.
    Future<void> pumpShell(WidgetTester tester, double scale) async {
      useWidth(tester, 360);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: const MainShell(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('360dp · 글자 $scale배에서 탭이 안 넘친다', (tester) async {
        await pumpShell(tester, scale);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('라벨이 잘리지 않는다 — "커뮤…" 는 무엇을 누르는지 알 수 없다', (tester) async {
      await pumpShell(tester, 2.0);

      for (final label in ['홈', '지도', '커뮤니티', '채팅']) {
        expect(find.text(label), findsOneWidget, reason: '$label 탭의 이름이 온전히 남아야 한다');
      }
    });

    testWidgets('탭 라벨은 1.3배에서 멈춘다 — 본문은 안 멈춘다', (tester) async {
      await pumpShell(tester, 2.0);

      final label = tester.renderObject<RenderBox>(find.text('커뮤니티'));
      final body = tester.renderObject<RenderBox>(find.text('아직 등록된 아이가 없어요'));

      expect(label.size.height, lessThan(body.size.height),
          reason: '표지판과 본문은 다르다 — 본문은 2.0배를 그대로 따른다');
    });
  });
}

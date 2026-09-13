// 메뉴바 — 좁은 폰 · 큰 글자에서 안 넘치고, 좌우가 대칭인가 — 이슈 #419 · #446.
//
// ## 왜 이 파일이 따로 있나
//
// `today_screen_text_scale_test` 가 탭 넘침을 이미 재고 있었지만 **360dp 한 폭**만 봤다.
// 다섯 칸(홈 · 지도 · 산책 · 커뮤니티 · 채팅)이 한 알약을 나눠 쓰면 360dp 에서 한 칸이
// 60dp 안팎이고 **320dp** 가 위험하다. 폭을 넷으로 늘려 잰다.
//
// ## 대칭을 잰다 (#446)
//
// 예전에는 왼쪽 셋 · 오른쪽 둘에 가운데 버튼이 바 위로 솟아 있었다 — 사장님이 "좌우 대칭이
// 전혀 안 맞고 가운데만 튀어나와 이상하다" 고 짚었다. 지금은 다섯 칸이 전부 같은 폭이고
// 산책이 가운데 칸 **안에** 있다. 그래서 라벨 다섯의 가운데가 **같은 간격**이고, 산책 라벨이
// 화면 한가운데이며, 산책 버튼이 알약 안에 든다 — 셋을 그대로 잰다. 넘침처럼 예외로
// 나오는 것이 아니라 그림이 틀어지는 것이라, 자로 재지 않으면 아무 검사도 안 잡는다.
//
// ## 넘침은 예외로 나온다
//
// Flutter 는 RenderFlex 넘침을 그리는 동안 예외로 던진다 — `tester.takeException()` 이
// 그걸 집는다. 그래서 넘침 검사는 "픽셀 몇 개" 를 안 세고 **예외가 없는 것**을 잰다.
//
// ## 테스트 폰트는 실제보다 넓다
//
// 위젯 테스트의 기본 폰트는 글자 하나가 정사각형이라 Pretendard 보다 넓다. 그래서 여기서
// 초록이면 실기기에서도 초록이다 — 그 반대는 아니다. **보수적인 쪽으로 틀린 검사**다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';

/// 왼쪽부터. 산책은 라벨은 있지만 **탭이 아니다** — 번호가 없다.
const _labels = ['홈', '지도', '산책', '커뮤니티', '채팅'];

/// 라벨 → 탭 번호. 산책이 가운데 칸을 차지하지만 번호는 안 먹는다 — 커뮤니티가 2, 채팅이 3.
const _tabs = {'홈': 0, '지도': 1, '커뮤니티': 2, '채팅': 3};

Future<void> _pumpShell(WidgetTester tester,
    {required double width, required double scale}) async {
  const ratio = 3.0;
  tester.view.physicalSize = Size(width * ratio, 780 * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      // 화면 크기는 view 에서 온 것을 그대로 두고 글자 배율만 바꾼다 — MediaQueryData 를
      // 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: const MainShell(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
    kMyPets.value = const [];
    AuthState.resetForTest();
    // 게스트로 둔다 — 서버를 안 부르고 셸이 온전히 그려진다.
    AuthState.status.value = AuthStatus.unauthenticated;
  });
  tearDown(AuthState.resetForTest);

  for (final width in [320.0, 360.0, 375.0, 393.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${width.toInt()}dp · 글자 $scale배에서 칸 다섯이 안 넘친다', (tester) async {
        await _pumpShell(tester, width: width, scale: scale);

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('가장 나쁜 조건(320dp · 2.0배)에서도 다섯 이름이 온전히 남는다', (tester) async {
    await _pumpShell(tester, width: 320, scale: 2.0);

    for (final label in _labels) {
      expect(find.text(label), findsOneWidget,
          reason: '"$label" 이 잘리면 무엇을 누르는지 알 수 없다');
    }
  });

  // 일정 탭이 빠지면서 **커뮤니티·채팅의 번호가 하나씩 당겨졌다**(#446). 라벨과 번호가
  // 어긋나면 사용자는 누른 것과 다른 화면에 도착하고, 그건 오류 없이 일어난다.
  //
  // 화면 자체를 띄워 확인하지 않는 이유: 각 화면이 뜨자마자 서버를 부른다. 여기서 그것을
  // 태우면 이 파일이 네 화면의 네트워크까지 재게 된다 — 그 몫은 각 화면의 테스트다.
  // 여기서는 **셸이 정하는 것**만 잰다.
  testWidgets('라벨과 탭 번호가 짝이 맞는다 — 커뮤니티 2 · 채팅 3', (tester) async {
    addTearDown(() => RootTab.index.value = 0);
    RootTab.index.value = 0;
    await _pumpShell(tester, width: 360, scale: 1.0);

    for (final entry in _tabs.entries) {
      RootTab.index.value = -1;

      // 누른 뒤 pump 하지 않는다 — 새 화면을 만들면 그 화면이 서버를 부른다.
      await tester.tap(find.text(entry.key));

      expect(RootTab.index.value, entry.value,
          reason: '"${entry.key}" 은 ${entry.value}번 탭이어야 한다');
    }
    RootTab.index.value = 0;
  });

  testWidgets('일정은 더 이상 탭이 아니다 — 홈에서 연다(#446)', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    expect(find.text('일정'), findsNothing,
        reason: '탭 다섯에 가운데 버튼까지 두면 좌우가 3:2 로 안 맞는다. 일정은 홈의 날짜 줄이 연다');
  });

  // ── 대칭 — 사장님이 짚은 그것 (#446)
  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets('${width.toInt()}dp — 다섯 칸이 같은 간격이고 산책이 한가운데다', (tester) async {
      await _pumpShell(tester, width: width, scale: 1.0);

      final xs = _labels.map((l) => tester.getCenter(find.text(l)).dx).toList();
      expect(xs, orderedEquals([...xs]..sort()),
          reason: '알약 안의 순서가 뒤집히면 번호가 맞아도 사람은 다른 것을 누른다');

      final gaps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
      for (final gap in gaps) {
        expect((gap - gaps.first).abs(), lessThan(1.0),
            reason: '칸 폭이 다르면 좌우 무게가 쏠린다 — 간격 $gaps');
      }

      expect((xs[2] - width / 2).abs(), lessThan(1.0),
          reason: '산책이 화면 한가운데(${width / 2})가 아니라 ${xs[2]} 에 있다');
    });
  }

  testWidgets('산책 버튼은 알약 안에 든다 — 위로 솟지 않는다', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    final pill = tester.getRect(find.ancestor(
      of: find.text('산책'),
      matching: find.byType(BackdropFilter),
    ));
    final button = tester.getRect(find.byIcon(Icons.directions_walk_rounded));

    expect(button.top, greaterThanOrEqualTo(pill.top),
        reason: '버튼 위가 알약 위(${pill.top})보다 높다(${button.top}) — 하나만 튀어나온 모양이다');
    expect(button.bottom, lessThanOrEqualTo(pill.bottom));
  });

  testWidgets('알약은 유리다 — 블러에 채도 보정이 붙어 있다', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    final filter = tester.widget<BackdropFilter>(find.ancestor(
      of: find.text('산책'),
      matching: find.byType(BackdropFilter),
    ));
    // 블러만 있으면 뒤가 회색으로 뿌옇다. compose 로 채도 행렬이 함께 있어야 유리처럼 비친다.
    expect(filter.filter.toString(), contains('compose'),
        reason: '블러 하나짜리 필터면 뒤가 흐린 회색이지 유리가 아니다');
  });

  testWidgets('산책 칸은 접근성 이름이 "산책 시작" 인 버튼이다', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    expect(find.bySemanticsLabel('산책 시작'), findsOneWidget);
  });
}

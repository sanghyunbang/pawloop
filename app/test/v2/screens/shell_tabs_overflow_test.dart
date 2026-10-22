// 메뉴바 — 좁은 폰 · 큰 글자에서 안 넘치고, 좌우가 대칭인가 — 이슈 #419 · #446.
//
// ## 왜 이 파일이 따로 있나
//
// `today_screen_text_scale_test` 가 탭 넘침을 이미 재고 있었지만 **360dp 한 폭**만 봤다.
// 다섯 칸(홈 · 지도 · 일정 · 커뮤니티 · 채팅)이 한 알약을 나눠 쓰면 360dp 에서 한 칸이
// 60dp 안팎이고 **320dp** 가 위험하다. 폭을 넷으로 늘려 잰다.
//
// ## 대칭을 잰다 (#446)
//
// 예전에는 왼쪽 셋 · 오른쪽 둘에 가운데 산책 버튼이 바 위로 솟아 있었다 — "좌우
// 대칭이 전혀 안 맞고 가운데만 튀어나와 이상하다" 고 짚었다. 그 뒤 산책을 가운데 칸에 넣고
// 일정을 홈으로 뺐는데, **일정 탭은 필수**라고 해서(2026-09-14) 산책을 바에서 빼고
// 홈의 "산책 시작" 에 맡겼다. 지금은 탭 다섯이 전부 같은 폭이고 가운데가 일정이다. 그래서
// 라벨 다섯의 간격이 **같고**, 일정이 화면 한가운데다 — 둘을 그대로 잰다. 넘침처럼 예외로
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

/// 왼쪽부터. 번호가 곧 자리다.
const _labels = ['홈', '탐색', '일정', '커뮤니티', '채팅'];

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
      testWidgets('${width.toInt()}dp · 글자 $scale배에서 탭 다섯이 안 넘친다', (tester) async {
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

  // 라벨과 번호가 어긋나면 사용자는 누른 것과 다른 화면에 도착하고, 그건 오류 없이 일어난다.
  //
  // 화면 자체를 띄워 확인하지 않는 이유: 각 화면이 뜨자마자 서버를 부른다. 여기서 그것을
  // 태우면 이 파일이 다섯 화면의 네트워크까지 재게 된다 — 그 몫은 각 화면의 테스트다.
  // 여기서는 **셸이 정하는 것**만 잰다.
  testWidgets('라벨과 탭 번호가 짝이 맞는다 — 홈0 지도1 일정2 커뮤니티3 채팅4', (tester) async {
    addTearDown(() => RootTab.index.value = 0);
    RootTab.index.value = 0;
    await _pumpShell(tester, width: 360, scale: 1.0);

    for (final (i, label) in _labels.indexed) {
      RootTab.index.value = -1;

      // 누른 뒤 pump 하지 않는다 — 새 화면을 만들면 그 화면이 서버를 부른다.
      await tester.tap(find.text(label));

      expect(RootTab.index.value, i, reason: '"$label" 은 $i번 탭이어야 한다');
    }
    RootTab.index.value = 0;
  });

  testWidgets('산책은 바에 없다 — 홈의 "산책 시작" 이 맡는다(#446, 2026-09-14)', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    expect(find.text('산책'), findsNothing,
        reason: '일정 탭이 필수라 가운데 버튼까지 두면 여섯이 된다 — 산책은 홈으로 뺐다');
    expect(find.byIcon(Icons.directions_walk_rounded), findsNothing);
  });

  // ── 대칭 — 그 지적 (#446)
  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets('${width.toInt()}dp — 다섯 칸이 같은 간격이고 일정이 한가운데다', (tester) async {
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
          reason: '가운데 칸(일정)이 화면 한가운데(${width / 2})가 아니라 ${xs[2]} 에 있다');
    });
  }

  testWidgets('알약은 유리다 — 블러에 채도 보정이 붙어 있다', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    final filter = tester.widget<BackdropFilter>(find.ancestor(
      of: find.text('일정'),
      matching: find.byType(BackdropFilter),
    ));
    // 블러만 있으면 뒤가 회색으로 뿌옇다. compose 로 채도 행렬이 함께 있어야 유리처럼 비친다.
    expect(filter.filter.toString(), contains('compose'),
        reason: '블러 하나짜리 필터면 뒤가 흐린 회색이지 유리가 아니다');
  });
}

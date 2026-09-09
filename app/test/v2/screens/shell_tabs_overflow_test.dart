// 탭 다섯이 좁은 폰 · 큰 글자에서 안 넘치는가 — 이슈 #419.
//
// ## 왜 이 파일이 따로 있나
//
// `today_screen_text_scale_test` 가 탭 넘침을 이미 재고 있었지만 **360dp 한 폭**만 봤다.
// #419 가 다섯째("일정")를 더하면서 한 칸이 좁아졌다 — 360dp 에서 넷일 때 59dp 였고
// 다섯이면 47dp 다. 그러면 **320dp** 가 새로 위험해진다. 폭을 넷으로 늘려 잰다.
//
// ## 넘침은 예외로 나온다
//
// Flutter 는 RenderFlex 넘침을 그리는 동안 예외로 던진다 — `tester.takeException()` 이
// 그걸 집는다. 그래서 이 테스트는 "픽셀 몇 개" 를 안 세고 **예외가 없는 것**을 잰다.
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

const _labels = ['홈', '지도', '일정', '커뮤니티', '채팅'];

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

  // 다섯째를 가운데에 끼워 넣으면서 **커뮤니티·채팅의 번호가 하나씩 밀렸다.** 라벨과
  // 번호가 어긋나면 사용자는 누른 것과 다른 화면에 도착하고, 그건 오류 없이 일어난다.
  //
  // 화면 자체를 띄워 확인하지 않는 이유: 각 화면이 뜨자마자 서버를 부른다. 여기서 그것을
  // 태우면 이 파일이 다섯 화면의 네트워크까지 재게 된다 — 그 몫은 각 화면의 테스트다
  // (`schedule_screen_test.dart`). 여기서는 **셸이 정하는 것**만 잰다.
  testWidgets('라벨과 탭 번호가 짝이 맞는다 — 커뮤니티가 채팅 번호를 갖게 되면 안 된다', (tester) async {
    addTearDown(() => RootTab.index.value = 0);
    RootTab.index.value = 0;
    await _pumpShell(tester, width: 360, scale: 1.0);

    for (final (i, label) in _labels.indexed) {
      RootTab.index.value = -1;

      // 누른 뒤 pump 하지 않는다 — 새 화면을 만들면 그 화면이 서버를 부르고, 그러면
      // 이 파일이 다섯 화면의 네트워크를 재게 된다. 셸은 한 번만 띄운 채로 둔다.
      await tester.tap(find.text(label));

      expect(RootTab.index.value, i, reason: '"$label" 은 $i번 탭이어야 한다');
    }
    RootTab.index.value = 0;
  });

  testWidgets('왼쪽부터 홈 · 지도 · 일정 · (기록) · 커뮤니티 · 채팅 순이다', (tester) async {
    await _pumpShell(tester, width: 360, scale: 1.0);

    final xs = _labels.map((l) => tester.getCenter(find.text(l)).dx).toList();

    expect(xs, orderedEquals([...xs]..sort()),
        reason: '알약 안의 순서가 뒤집히면 번호가 맞아도 사람은 다른 것을 누른다');
  });
}

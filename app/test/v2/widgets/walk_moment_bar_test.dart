// 산책 중 한 손 기록 줄 — 이슈 #340.
//
// 완료 조건 넷째("버튼이 한 손 엄지 범위에 있고 최소 56dp")는 눈으로만 확인하면 다음
// 디자인 손질에서 조용히 깨진다. 그래서 크기를 여기서 잰다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/walk_moment.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_moment_bar.dart';

Future<List<WalkMomentKind>> _pump(
  WidgetTester tester, {
  WalkMomentTally tally = const WalkMomentTally({}),
  WalkMomentKind? undoable,
}) async {
  final taps = <WalkMomentKind>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: WalkMomentBar(tally: tally, undoable: undoable, onTap: taps.add),
      ),
    ),
  ));
  return taps;
}

void main() {
  testWidgets('세 버튼이 이름과 함께 보인다', (tester) async {
    await _pump(tester);

    expect(find.text('배변'), findsOneWidget);
    expect(find.text('마킹'), findsOneWidget);
    expect(find.text('물'), findsOneWidget);
  });

  testWidgets('버튼 하나가 최소 56dp 다 — 걸으면서 누르는 크기', (tester) async {
    await _pump(tester);

    for (final label in ['배변', '마킹', '물']) {
      final size = tester.getSize(find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      ).first);
      expect(size.height, greaterThanOrEqualTo(WalkMomentBar.minTapSize),
          reason: '$label 버튼이 손가락 권장치보다 작으면 걸으면서 못 누른다');
      expect(size.width, greaterThanOrEqualTo(WalkMomentBar.minTapSize));
    }
  });

  testWidgets('누르면 그 종류를 그대로 넘긴다 — 기록할지 취소할지는 화면이 정한다', (tester) async {
    final taps = await _pump(tester);

    await tester.tap(find.text('배변'));
    await tester.tap(find.text('물'));
    await tester.pump();

    expect(taps, [WalkMomentKind.poop, WalkMomentKind.water]);
  });

  testWidgets('센 만큼 배지가 붙고, 0 이면 안 붙는다', (tester) async {
    await _pump(
      tester,
      tally: WalkMomentTally.of(const [
        WalkMoment(kind: WalkMomentKind.poop, tSec: 10),
        WalkMoment(kind: WalkMomentKind.poop, tSec: 40),
      ]),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsNothing,
        reason: '안 한 일을 0 으로 적으면 못 한 것처럼 읽힌다');
  });

  testWidgets('취소 창이 열린 버튼만 "다시 누르면 취소" 를 말한다', (tester) async {
    await _pump(
      tester,
      tally: WalkMomentTally.of(const [WalkMoment(kind: WalkMomentKind.poop, tSec: 10)]),
      undoable: WalkMomentKind.poop,
    );

    expect(find.text('다시 누르면 취소'), findsOneWidget);
    expect(find.text('배변'), findsNothing, reason: '그 자리를 안내가 차지한다');
    expect(find.text('마킹'), findsOneWidget, reason: '다른 버튼은 그대로다');
  });
}

// 트래킹 스탯 패널 — 종료가 첫 프레임부터 보이는가 (#327).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/widgets/walk_stats_panel.dart';

Widget _wrap({
  required bool expanded,
  bool paused = false,
  VoidCallback? onToggle,
  VoidCallback? onPause,
  VoidCallback? onFinish,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: WalkStatsPanel(
            km: 0.32,
            timeLabel: '00:42',
            paceLabel: "2'10\"",
            paused: paused,
            expanded: expanded,
            onToggle: onToggle ?? () {},
            onPauseToggle: onPause ?? () {},
            onFinish: onFinish ?? () {},
          ),
        ),
      ),
    );

void main() {
  test('트래킹 화면의 기본은 펼침이다 — 종료를 한 번 더 눌러 꺼내지 않는다', () {
    expect(WalkStatsPanel.expandedByDefault, isTrue);
  });

  testWidgets('펼침: 거리·시간·페이스와 일시정지·종료가 보인다', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true));

    expect(find.text('종료'), findsOneWidget);
    expect(find.text('일시정지'), findsOneWidget);
    expect(find.text('0.32'), findsOneWidget);
    expect(find.text('00:42'), findsOneWidget);
    expect(find.text("2'10\""), findsOneWidget);
    expect(find.text('산책 기록 중'), findsOneWidget);
  });

  testWidgets('접힘: 알약 하나, 종료는 없다 — 탭하면 onToggle', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(_wrap(expanded: false, onToggle: () => toggled++));

    expect(find.text('0.32km · 00:42'), findsOneWidget);
    expect(find.text('종료'), findsNothing);

    await tester.tap(find.text('0.32km · 00:42'));
    expect(toggled, 1);
  });

  testWidgets('종료와 일시정지가 콜백을 부른다', (tester) async {
    var finished = 0;
    var paused = 0;
    await tester.pumpWidget(_wrap(expanded: true, onFinish: () => finished++, onPause: () => paused++));

    await tester.tap(find.text('종료'));
    await tester.tap(find.text('일시정지'));
    expect(finished, 1);
    expect(paused, 1);
  });

  testWidgets('일시정지 중엔 "재개" 와 "일시정지됨"', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true, paused: true));

    expect(find.text('재개'), findsOneWidget);
    expect(find.text('일시정지됨'), findsOneWidget);
    expect(find.text('종료'), findsOneWidget, reason: '멈춰 있어도 끝낼 수 있어야 한다');
  });
}

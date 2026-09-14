// 순간 막대의 넷째 칸 — 산책 중 카메라 (#450). 막대는 자리만 내주고, 버튼은 화면이 준다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/walk_moment.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_moment_bar.dart';

void main() {
  testWidgets('trailing 을 주면 순간 셋 뒤에 같은 폭으로 선다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkMomentBar(
          tally: WalkMomentTally.of(const []),
          onTap: (_) {},
          trailing: const Text('사진', key: Key('camera')),
        ),
      ),
    ));

    expect(find.byKey(const Key('camera')), findsOneWidget);
    final expanded = tester.widgetList<Expanded>(find.byType(Expanded)).toList();
    expect(expanded, hasLength(4), reason: '배변 · 마킹 · 물 + 카메라');
    expect(expanded.map((e) => e.flex).toSet(), {1}, reason: '넷이 같은 폭');
  });

  testWidgets('trailing 이 없으면 셋뿐이다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkMomentBar(tally: WalkMomentTally.of(const []), onTap: (_) {}),
      ),
    ));

    expect(find.byType(Expanded), findsNWidgets(3));
    expect(find.text('사진'), findsNothing);
  });
}

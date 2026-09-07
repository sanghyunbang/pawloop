// 위치를 잡는 동안 — 스피너만 있던 보라 화면에 말이 생겼다 (#327).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/widgets/walk_locating_view.dart';

void main() {
  testWidgets('기다리는 이유와 빨라지는 조건을 말한다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WalkLocatingView()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('위치를 잡는 중이에요'), findsOneWidget);
    expect(find.text('하늘이 보이는 곳이면 빨라요'), findsOneWidget);
  });
}

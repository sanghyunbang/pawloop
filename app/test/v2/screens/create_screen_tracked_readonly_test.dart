// 산책 기록 저장 화면 — GPS 로 잰 값은 고칠 수 없다 (#327).
//
// 트래킹이 만든 초안으로 열리면 거리·시간에 ± 가 없고 소수 둘째 자리(0.15 km)다.
// 손입력으로 열리면 ± 가 있다. 사진 더미 타일은 어느 쪽에도 없다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/screens/create_screen.dart';

WalkDraft _tracked() => WalkDraft.fresh(
      startedAt: DateTime(2026, 9, 7, 9, 0),
      endedAt: DateTime(2026, 9, 7, 9, 1, 16),
      distanceM: 150,
      durationS: 76,
      path: const [],
    );

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('GPS 초안: ± 가 없고 0.15 km 로 보인다', (t) async {
    await _pump(t, CreateScreen(draft: _tracked()));

    expect(find.byIcon(Icons.remove), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text('0.15 km'), findsOneWidget);
    expect(find.text('1 분'), findsOneWidget);
    expect(find.textContaining('GPS 로 잰 값이에요'), findsOneWidget);
  });

  testWidgets('손입력: ± 가 있고 기본값 안내가 있다', (t) async {
    await _pump(t, const CreateScreen());

    expect(find.byIcon(Icons.remove), findsNWidgets(2));
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    expect(find.textContaining('직접 입력하는 값이에요'), findsOneWidget);
  });

  testWidgets('사진 더미 타일이 없다 — 붙일 수 없는 사진을 붙은 것처럼 그리지 않는다', (t) async {
    await _pump(t, CreateScreen(draft: _tracked()));

    expect(find.text('사진'), findsNothing);
    expect(find.text('추가'), findsNothing);
    expect(find.byIcon(Icons.add_a_photo), findsNothing);
  });
}

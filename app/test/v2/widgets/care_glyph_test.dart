// 항목의 그림 — 이슈 #560. 에뮬레이터에서 보고 고친 둘을 잠근다.
//
// 1. **배변·마킹은 산책 바와 같은 그림**이어야 한다. 예전에는 산책 바가 직접 그리고 카드는
//    머티리얼 아이콘(잎사귀·물방울)을 써서, 같은 뜻에 그림이 둘이었다 — `walk_moment_bar`
//    머리말이 하지 말라고 적어 둔 바로 그것이다. 게다가 카드의 마킹은 물과 거의 같은
//    물방울이라 둘 다 아직인 날에는 같은 그림이 나란히 앉았다.
//
// 2. **모르는 열쇠말이 체크로 떨어지면 안 된다.** 카드는 완료한 칸을 체크로 그린다 —
//    모르는 값이 체크가 되면 아직 안 한 칸이 한 것처럼 보인다. `기타` 가 실제로 그렇게
//    그려지고 있었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/care_icons.dart';
import 'package:heat_trip_flutter/v2/widgets/care_glyph.dart';

Future<void> _pump(WidgetTester t, String key) async {
  await t.pumpWidget(MaterialApp(
    home: Center(child: CareGlyph(iconKey: key, size: 20, color: Colors.black)),
  ));
}

/// 그 위젯이 쓰는 화가. 아이콘이면 `null` 이다.
CustomPainter? _painterOf(WidgetTester t) {
  final found = t.widgetList<CustomPaint>(find.descendant(
    of: find.byType(CareGlyph),
    matching: find.byType(CustomPaint),
  ));
  for (final paint in found) {
    if (paint.painter != null) return paint.painter;
  }
  return null;
}

void main() {
  testWidgets('배변·마킹은 직접 그린다 — 산책 바와 같은 화가다', (t) async {
    await _pump(t, 'poop');
    expect(_painterOf(t), isA<CarePoopPainter>());

    await _pump(t, 'pee');
    expect(_painterOf(t), isA<CarePeePainter>(),
        reason: '물방울 아이콘으로 되돌리면 물(water_drop)과 눈으로 안 갈린다');
  });

  testWidgets('나머지는 아이콘이다', (t) async {
    await _pump(t, 'meal');

    expect(_painterOf(t), isNull);
    expect(t.widget<Icon>(find.byType(Icon)).icon, Icons.restaurant_rounded);
  });

  group('careItemIcon', () {
    test('모르는 열쇠말이 체크가 아니다 — 카드의 "완료" 와 같은 그림이면 안 된다', () {
      expect(careItemIcon('한글이든무엇이든'), isNot(Icons.check_circle_rounded));
      expect(careItemIcon('한글이든무엇이든'), isNot(Icons.check_circle_outline_rounded));
    });

    test('기타도 체크가 아니다 — 고르는 목록에서 "선택됨" 으로 읽혔다', () {
      expect(careItemIcon('etc'), isNot(Icons.check_circle_rounded));
      expect(careItemIcon('etc'), isNot(Icons.check_circle_outline_rounded));
      expect(careItemIcon('etc'), isNot(careItemIcon('모르는값')),
          reason: '기타는 제 그림이 있어야 한다 — 기본 그림으로 떨어지면 뜻이 없다');
    });

    test('물과 마킹이 서로 다른 그림이다', () {
      expect(careItemIcon('water'), isNot(careItemIcon('pee')));
    });

    test('고르는 목록의 모든 열쇠말이 제 그림을 가진다 — 기본 그림으로 떨어지면 안 된다', () {
      final fallback = careItemIcon('이건분명히없는값');
      final fallenBack =
          kCareIconKeys.where((key) => careItemIcon(key) == fallback).toList();

      expect(fallenBack, isEmpty,
          reason: '고르라고 보여 주는 칩이 전부 같은 그림이면 고를 수가 없다');
    });
  });
}

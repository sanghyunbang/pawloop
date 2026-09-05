// 산책 완료 시트 — 이슈 #310. 경로 사진이 갤러리로만 가는가, 실패가 화면을 안 죽이는가.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/walk/route_image.dart';
import 'package:heat_trip_flutter/v2/walk/route_photo_saver.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_finish_sheet.dart';

const _path = [
  [127.0374, 37.5445],
  [127.0402, 37.5455],
  [127.0420, 37.5430],
];

final _fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

({Widget sheet, List<String> savedNames, List<Uint8List> savedBytes, List<String> events}) fixture({
  List<List<double>> path = _path,
  RoutePhotoException? saveFails,
}) {
  final names = <String>[];
  final bytes = <Uint8List>[];
  final events = <String>[];
  final sheet = WalkFinishSheet(
    timeLabel: '18:40',
    distanceLabel: '1.24km',
    paceLabel: "15'03\"",
    art: RouteArt(
      lngLat: path,
      distanceLabel: '1.24km',
      timeLabel: '18:40',
      dateLabel: WalkFinishSheet.dateLabel(DateTime(2026, 9, 6, 14, 20)),
    ),
    walkedAt: DateTime(2026, 9, 6, 14, 20),
    // 렌더러는 가짜 — 실제 PNG 는 route_image_test 가 잰다. 여기서는 "만든 바이트가 그대로
    // 저장기로 가는가" 만 본다.
    renderer: (_) async => _fakePng,
    saver: RoutePhotoSaver.fake((b, name) async {
      if (saveFails != null) throw saveFails;
      bytes.add(b);
      names.add(name);
    }),
    onSave: () => events.add('save'),
    onDiscard: () => events.add('discard'),
    warm: const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
  );
  return (sheet: sheet, savedNames: names, savedBytes: bytes, events: events);
}

Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: sheet))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('요약 셋과 경로 미리보기, "경로 사진 저장" 이 보인다', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    expect(find.text('산책 완료! 🐾'), findsOneWidget);
    expect(find.text('18:40'), findsOneWidget);
    expect(find.text('1.24km'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets, reason: '타일 없이 그린 경로 미리보기');
    expect(find.text('경로 사진 저장'), findsOneWidget);
  });

  testWidgets('"경로 사진 저장" → 렌더한 PNG 가 저장기로 가고 이름은 pawloop_walk_출발시각', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('경로 사진 저장'));
    await tester.pumpAndSettle();

    expect(f.savedBytes, [_fakePng]);
    expect(f.savedNames, ['pawloop_walk_20260906_1420']);
    expect(find.text('갤러리에 저장했어요 · 앨범 Pawloop'), findsOneWidget);
    expect(find.text('갤러리에 저장했어요'), findsOneWidget, reason: '버튼이 저장됨으로 바뀐다');

    // 두 번 눌러도 두 장이 되지 않는다
    await tester.tap(find.text('갤러리에 저장했어요'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(f.savedBytes, hasLength(1));
  });

  testWidgets('점이 둘 미만이면 미리보기도 저장 버튼도 없고 이유를 한 줄 적는다', (tester) async {
    final f = fixture(path: const [[127.0374, 37.5445]]);
    await pumpSheet(tester, f.sheet);

    expect(find.text('경로 사진 저장'), findsNothing);
    expect(find.text('경로가 짧아 그림은 못 만들었어요'), findsOneWidget);
    expect(find.text('기록 저장하기'), findsOneWidget, reason: '기록 저장은 경로와 무관하게 된다');
  });

  testWidgets('사진 권한이 없으면 문구를 보여 주고 시트는 살아 있다 — 기록 저장은 여전히 된다', (tester) async {
    final f = fixture(saveFails: const RoutePhotoException(RoutePhotoFailure.permissionDenied));
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('경로 사진 저장'));
    await tester.pumpAndSettle();

    expect(find.text('사진 저장 권한이 없어요 · 설정에서 허용해 주세요'), findsOneWidget);
    expect(f.savedBytes, isEmpty);
    expect(find.text('경로 사진 저장'), findsOneWidget, reason: '다시 누를 수 있어야 한다');

    await tester.tap(find.text('기록 저장하기'));
    expect(f.events, ['save']);
  });

  testWidgets('"저장 안 함" 은 onDiscard 를 부른다', (tester) async {
    final f = fixture();
    await pumpSheet(tester, f.sheet);

    await tester.tap(find.text('저장 안 함'));
    expect(f.events, ['discard']);
  });
}

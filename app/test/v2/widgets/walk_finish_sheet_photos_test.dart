// 끝내기 시트의 사진 띠와 공유 카드의 사진 배경 — 이슈 #450.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:heat_trip_flutter/v2/walk/route_image.dart';
import 'package:heat_trip_flutter/v2/walk/route_photo_saver.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_finish_sheet.dart';

const _path = [
  [127.0374, 37.5445],
  [127.0402, 37.5455],
  [127.0420, 37.5430],
];

WalkFinishSheet _sheet({
  List<String> photoPaths = const [],
  Future<Uint8List?> Function(String path)? readPhoto,
  List<WalkShareCard>? shared,
}) =>
    WalkFinishSheet(
      timeLabel: '18:40',
      distanceLabel: '1.24km',
      paceLabel: "15'03\"",
      art: RouteArt(
        lngLat: _path,
        distanceLabel: '1.24km',
        timeLabel: '18:40',
        dateLabel: WalkFinishSheet.dateLabel(DateTime(2026, 9, 14, 7, 20)),
        moments: const [],
      ),
      walkedAt: DateTime(2026, 9, 14, 7, 20),
      saver: RoutePhotoSaver.fake((_, __) async {}),
      renderer: (_) async => Uint8List(0),
      onSave: () {},
      onDiscard: () {},
      warm: const LinearGradient(colors: [Color(0xFFFF8F4D), Color(0xFFE04A2B)]),
      dogName: '보리',
      shareCard: (card) async => shared?.add(card),
      photoPaths: photoPaths,
      readPhoto: readPhoto ?? (_) async => null,
    );

Future<void> _pump(WidgetTester tester, Widget sheet) async {
  tester.view.physicalSize = const Size(393 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: sheet))));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('finish_photos_'));
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('사진이 있으면 요약 아래에 띠와 "사진 N장 · 기록에 같이 남아요" — 없으면 줄이 없다', (tester) async {
    final a = File('${tmp.path}${Platform.pathSeparator}a.jpg')..writeAsBytesSync([1]);
    final b = File('${tmp.path}${Platform.pathSeparator}b.jpg')..writeAsBytesSync([1]);
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
    final read = <String>[];

    await _pump(tester, _sheet(photoPaths: [a.path, b.path], readPhoto: (path) async {
      read.add(path);
      return png;
    }));

    expect(find.byKey(const Key('finish-photos')), findsOneWidget);
    expect(read, [a.path, b.path], reason: '띠의 그림은 시트가 파일을 열지 않고 readPhoto 로 받는다(#310 잠금)');
    expect(find.descendant(of: find.byKey(const Key('finish-photos')), matching: find.byType(Image)),
        findsNWidgets(2));
    expect(find.text('사진 2장\n기록에 같이 남아요'), findsOneWidget);
    expect(find.text('기록 저장하기'), findsOneWidget, reason: '저장 버튼은 그대로');

    await _pump(tester, _sheet());
    expect(find.byKey(const Key('finish-photos')), findsNothing);
  });

  testWidgets('공유하면 첫 사진의 바이트가 카드의 배경으로 간다', (tester) async {
    final shared = <WalkShareCard>[];
    final read = <String>[];
    await _pump(tester, _sheet(
      photoPaths: const ['/p/first.jpg', '/p/second.jpg'],
      readPhoto: (path) async {
        read.add(path);
        return Uint8List.fromList([9, 9, 9]);
      },
      shared: shared,
    ));

    await tester.tap(find.text('공유하기'));
    await tester.pumpAndSettle();

    expect(read, ['/p/first.jpg', '/p/second.jpg'],
        reason: '띠가 한 번씩 읽고, 공유는 그 바이트를 다시 쓴다 — 파일을 두 번 열지 않는다');
    expect(shared.single.photo, [9, 9, 9]);
    expect(shared.single.hasPhoto, isTrue);
  });

  testWidgets('사진이 없으면 카드에 사진이 없다 — 예전 카드 그대로', (tester) async {
    final shared = <WalkShareCard>[];
    await _pump(tester, _sheet(shared: shared));

    await tester.tap(find.text('공유하기'));
    await tester.pumpAndSettle();

    expect(shared.single.photo, isNull);
  });
}

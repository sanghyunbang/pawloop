// 저장 화면의 사진 카드와 기록 상세의 사진 띠 — 이슈 #450.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/create_screen.dart';
import 'package:heat_trip_flutter/v2/screens/walk_detail_screen.dart';

class _Walks implements WalkRepository {
  @override
  Future<List<ServerPet>> pets() async => const [
        ServerPet(id: 1, name: 'Bori', species: ServerPetSpecies.dog, size: ServerPetSize.medium, neutered: false),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(393 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('walk_photo_screens_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('저장 화면: 초안에 사진이 있으면 "사진 N장 · 저장하면 같이 올라가요" 카드가 맨 위다', (tester) async {
    final a = File('${tmp.path}${Platform.pathSeparator}a.jpg')..writeAsBytesSync([1]);
    final draft = WalkDraft.fresh(
      startedAt: DateTime(2026, 9, 14, 7),
      endedAt: DateTime(2026, 9, 14, 7, 30),
      distanceM: 1200,
      durationS: 1800,
      path: const [],
      photoPaths: [a.path],
    );

    await _pump(tester, CreateScreen(draft: draft, repository: _Walks()));

    expect(find.byKey(const Key('create-photos')), findsOneWidget);
    expect(find.text('사진 1장 · 저장하면 같이 올라가요'), findsOneWidget);
  });

  testWidgets('저장 화면: 사진 없는 초안은 카드가 없다', (tester) async {
    final draft = WalkDraft.fresh(
      startedAt: DateTime(2026, 9, 14, 7),
      endedAt: DateTime(2026, 9, 14, 7, 30),
      distanceM: 1200,
      durationS: 1800,
      path: const [],
    );

    await _pump(tester, CreateScreen(draft: draft, repository: _Walks()));

    expect(find.byKey(const Key('create-photos')), findsNothing);
  });

  testWidgets('기록 상세: 사진 URL 이 있으면 요약 위에 띠, 없으면 없다', (tester) async {
    await _pump(tester, WalkDetailScreen(
      walkId: 7,
      startedAt: DateTime(2026, 9, 14, 7),
      km: 1.2,
      durationS: 30 * 60,
      initialMemo: '',
      photoUrls: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
      repository: _Walks(),
    ));

    final strip = find.byKey(const Key('detail-photos'));
    expect(strip, findsOneWidget);
    expect(find.descendant(of: strip, matching: find.byType(Image)), findsNWidgets(2));

    await _pump(tester, WalkDetailScreen(
      walkId: 7,
      startedAt: DateTime(2026, 9, 14, 7),
      km: 1.2,
      durationS: 30 * 60,
      initialMemo: '',
      repository: _Walks(),
    ));
    expect(find.byKey(const Key('detail-photos')), findsNothing);
  });
}

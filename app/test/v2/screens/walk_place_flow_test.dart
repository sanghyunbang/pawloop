// 발견 → 기록: 지도에서 "여기서 산책 시작", 저장 화면의 이름 검색, 통계의 "자주 가는 곳" (#338).
//
// 검색은 **기기 안 카탈로그**에서 돈다. 검색어가 서버로 나가면 좌표를 안 보내면서 "서울숲"
// 을 보내는 셈이라, 앞문을 잠그고 뒷문을 여는 것이 된다(#235).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/place_catalog_repository.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/create_screen.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

PetPlace _place(
  String id,
  String title, {
  String source = 'kto',
  String category = '',
  String contentTypeId = '',
  double distM = 0,
}) =>
    PetPlace(
      contentId: id,
      title: title,
      source: source,
      category: category,
      contentTypeId: contentTypeId,
      addr: '서울특별시 성동구',
      image: '',
      tel: '',
      lat: 37.5445,
      lng: 127.0374,
      distM: distM,
    );

final _park = _place('2733967', '서울숲', contentTypeId: '12', distM: 174);
final _vet = _place('vet:1', '성수 동물병원', source: 'vet', category: 'vet', distM: 193);

class _FakeRepo extends PetPlacesRepository {
  _FakeRepo()
      : super(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://unused',
        );

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async =>
      switch (contentTypeId) {
        'vet' => [_vet],
        '12' => [_park],
        _ => [_park, _vet],
      };
}

/// 기기 안 카탈로그를 임시 폴더에 심는다 — 네트워크를 타지 않는다.
Future<PlaceCatalogRepository> _catalogWith(Directory dir, List<Map<String, Object?>> rows) async {
  final client = MockClient((_) async => http.Response.bytes(
        utf8.encode(jsonEncode(rows)),
        200,
        headers: {'etag': '"t"', 'content-type': 'application/json'},
      ));
  final repo = PlaceCatalogRepository(
    client: client,
    baseUrl: 'https://example.test',
    cacheDirectory: () async => dir,
  );
  await repo.all();
  return repo;
}

List<Map<String, Object?>> _catalogRows() => [
      {
        'contentId': '2733967',
        'title': '서울숲',
        'source': 'kto',
        'contentTypeId': '12',
        'lat': 37.5445,
        'lng': 127.0374,
        'addr': '서울 성동구',
      },
      {
        'contentId': '999',
        'title': '숲속작은도서관',
        'source': 'kto',
        'contentTypeId': '14',
        'lat': 37.5450,
        'lng': 127.0380,
        'addr': '서울 성동구',
      },
    ];

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('walk_place_flow');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('기기 안 이름 검색', () {
    test('검색어로 시작하는 것이 먼저, 그 다음 짧은 이름', () async {
      final catalog = await _catalogWith(tempDir, _catalogRows());

      final hits = await catalog.search('숲');

      expect(hits.map((p) => p.title).toList(), ['숲속작은도서관', '서울숲']);
    });

    test('빈 검색어면 빈 목록 — 카탈로그 전체를 쏟지 않는다', () async {
      final catalog = await _catalogWith(tempDir, _catalogRows());

      expect(await catalog.search('   '), isEmpty);
    });
  });

  group('저장 화면의 장소', () {
    testWidgets('목록에서 고르면 식별자가 붙는다 — 손으로 적으면 이름만', (tester) async {
      // 카탈로그 준비는 **진짜 파일 I/O** 라 위젯 테스트의 가짜 시간 안에서는 끝나지 않는다.
      // runAsync 밖에서 부르면 테스트가 그대로 멈춘다 — 실제로 그렇게 멈췄다.
      late PlaceCatalogRepository catalog;
      await tester.runAsync(() async => catalog = await _catalogWith(tempDir, _catalogRows()));
      await _pumpWide(tester, CreateScreen(catalog: catalog));

      await tester.enterText(find.byType(TextField).first, '서울숲');
      await tester.pumpAndSettle();
      expect(find.text('서울숲'), findsWidgets);

      await tester.tap(find.text('서울숲').last);
      await tester.pumpAndSettle();

      // 고른 뒤에는 "직접 적은 이름" 안내가 사라진다.
      expect(find.textContaining('직접 적은 이름은'), findsNothing);
    });

    testWidgets('카탈로그에 없는 이름을 적으면 안내가 뜬다 — 이 기록에만 남는다고 말한다', (tester) async {
      // 카탈로그 준비는 **진짜 파일 I/O** 라 위젯 테스트의 가짜 시간 안에서는 끝나지 않는다.
      // runAsync 밖에서 부르면 테스트가 그대로 멈춘다 — 실제로 그렇게 멈췄다.
      late PlaceCatalogRepository catalog;
      await tester.runAsync(() async => catalog = await _catalogWith(tempDir, _catalogRows()));
      await _pumpWide(tester, CreateScreen(catalog: catalog));

      await tester.enterText(find.byType(TextField).first, '우리 아파트 뒷길');
      await tester.pumpAndSettle();

      expect(find.textContaining('직접 적은 이름은'), findsOneWidget);
    });

    testWidgets('초안이 장소를 들고 오면 이름 칸이 그것으로 채워진다', (tester) async {
      late PlaceCatalogRepository catalog;
      await tester.runAsync(() async => catalog = await _catalogWith(tempDir, _catalogRows()));
      final draft = WalkDraft.fresh(
        startedAt: DateTime(2026, 9, 7, 13),
        endedAt: DateTime(2026, 9, 7, 13, 30),
        distanceM: 1200,
        durationS: 1800,
        path: const [],
        place: const WalkPlaceRef(title: '서울숲', source: 'kto', contentId: '2733967'),
      );

      await _pumpWide(tester, CreateScreen(draft: draft, catalog: catalog));

      expect(find.widgetWithText(TextField, '서울숲'), findsOneWidget);
      expect(find.textContaining('직접 적은 이름은'), findsNothing);
    });
  });

  group('지도에서 산책으로', () {
    testWidgets('걸을 만한 곳에는 "여기서 산책 시작" 이 있다', (tester) async {
      await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

      await tester.tap(find.text('서울숲'));
      await tester.pumpAndSettle();

      expect(find.text('여기서 산책 시작'), findsOneWidget);
    });

    testWidgets('병원에는 없다 — 거기서 산책을 시작한다는 말이 어색하다', (tester) async {
      await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

      await tester.tap(find.text('성수 동물병원'));
      await tester.pumpAndSettle();

      expect(find.text('여기서 산책 시작'), findsNothing);
      expect(find.text('길찾기'), findsOneWidget, reason: '다른 동작은 그대로다');
    });
  });
}

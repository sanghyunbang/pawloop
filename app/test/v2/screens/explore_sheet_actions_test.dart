// 지도 탐색 — 시트의 주 동작 · 산책로 머리와 먼 코스 안내 · 자리표시 카드 (#328).
//
// 리스트 뷰만 세운다(지도 SDK 는 테스트에 없다). 전화·길찾기는 `ExternalMaps.launcher` 를
// 갈아 끼워 어느 URI 를 열었는지 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

PetPlace _place(
  String id,
  String title, {
  String source = 'kto',
  String category = '',
  String contentTypeId = '',
  String tel = '',
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
      tel: tel,
      lat: 37.5445,
      lng: 127.0374,
      distM: distM,
    );

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
        'trail' => [
            _place('trail:41', 'DMZ 평화의 길 4-1코스', source: 'trail', category: 'trail', distM: 19800),
          ],
        'vet' => [
            _place('vet:1', '성수 숲속 피부과 동물병원', source: 'vet', category: 'vet', tel: '02-123-4567', distM: 327),
          ],
        _ => [
            _place('vet:1', '성수 숲속 피부과 동물병원', source: 'vet', category: 'vet', tel: '02-123-4567', distM: 327),
            _place('100', '서울숲', contentTypeId: '12', distM: 354),
            _place('101', '문리', contentTypeId: '38', distM: 263),
          ],
      };
}

Finder _chip(String label) => find.text(label).first;

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  // 지도가 내 동네를 기기에서 읽는다(#342). 목을 안 깔면 그 읽기가 안 끝나
  // 화면이 멈춘다 — pumpAndSettle 이 시간 초과로 죽는다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final original = ExternalMaps.launcher;
  tearDown(() => ExternalMaps.launcher = original);

  testWidgets('자리표시 "우리 동네 업체 자리" 카드가 없다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    expect(find.text('우리 동네 업체 자리'), findsNothing);
    expect(find.textContaining('제휴'), findsNothing);
    expect(find.textContaining('반려동반 가능 · 3곳'), findsOneWidget);
  });

  testWidgets('병원 시트: 전화 · 길찾기가 먼저, 글쓰기는 그 아래 — 전화는 tel: 을 연다', (tester) async {
    final opened = <Uri>[];
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(find.text('성수 숲속 피부과 동물병원'));
    await tester.pumpAndSettle();

    expect(find.text('전화'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('이 장소로 글쓰기'), findsOneWidget);
    expect(find.text('지도에서 보기'), findsNothing, reason: '병원은 선이 없다');

    await tester.tap(find.text('전화'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'tel:021234567');

    await tester.tap(find.text('길찾기'));
    await tester.pumpAndSettle();
    expect(opened.last.scheme, 'nmap');
    expect(opened.last.queryParameters['dname'], '성수 숲속 피부과 동물병원');
  });

  testWidgets('산책로 칩: 머리가 "가까운 산책로" 이고 8km 밖이면 그 말을 한다, 시트엔 지도에서 보기', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    expect(find.textContaining('가까운 산책로 · 1곳'), findsOneWidget);
    expect(find.textContaining('반려동반 가능 ·'), findsNothing);
    expect(find.text('가장 가까운 코스는 19.8km 밖이에요'), findsOneWidget);

    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();
    expect(find.text('지도에서 보기'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('전화'), findsNothing);
  });

  testWidgets('가까운 코스가 8km 안이면 안내가 없다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.tap(_chip('동물병원'));
    await tester.pumpAndSettle();

    expect(find.textContaining('동물병원 · 1곳'), findsOneWidget);
    expect(find.textContaining('밖이에요'), findsNothing);
  });
}

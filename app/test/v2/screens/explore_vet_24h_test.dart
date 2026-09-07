// 지도 — 병원의 24시 배지와 빠른 필터 (#337).
//
// 진료시간을 주는 공공 데이터가 없어서 이름으로 짐작한다. 그래서 이 테스트가 지키는 것은
// "거른다" 만이 아니라 **"이름 기준" 이라고 함께 적는다** 까지다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/vet_badge.dart';

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
      tel: '02-123-4567',
      lat: 37.5445,
      lng: 127.0374,
      distM: distM,
    );

final _vet24 = _place('vet:1', '24시 성수동물의료센터', source: 'vet', category: 'vet', distM: 210);
final _vetDay = _place('vet:2', '행복한 동물병원', source: 'vet', category: 'vet', distM: 330);
final _park = _place('100', '서울숲', contentTypeId: '12', distM: 354);

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
        'vet' => [_vet24, _vetDay],
        '12' => [_park],
        _ => [_vet24, _vetDay, _park],
      };
}

Future<void> _pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ExploreScreen(repository: _FakeRepo())));
  await tester.pumpAndSettle();
}

void main() {
  // 지도가 내 동네를 기기에서 읽는다(#342). 목을 안 깔면 그 읽기가 안 끝나
  // 화면이 멈춘다 — pumpAndSettle 이 시간 초과로 죽는다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('이름에 24시가 있는 병원 시트에만 배지 — "이름 기준" 을 함께 적는다', (tester) async {
    await _pumpWide(tester);

    await tester.tap(find.text('24시 성수동물의료센터'));
    await tester.pumpAndSettle();
    expect(find.byType(VetTwentyFourBadge), findsOneWidget);
    expect(find.text(VetTwentyFourBadge.label), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('행복한 동물병원'));
    await tester.pumpAndSettle();
    expect(find.byType(VetTwentyFourBadge), findsNothing);
  });

  testWidgets('24시 칩은 병원 칩 안에서만 나오고, 켜면 이름 기준으로 거른다', (tester) async {
    await _pumpWide(tester);

    expect(find.text('24시'), findsNothing, reason: '전체 칩에서는 뜻이 없다');

    await tester.tap(find.text('동물병원').first);
    await tester.pumpAndSettle();
    expect(find.text('24시'), findsOneWidget);
    expect(find.text('행복한 동물병원'), findsOneWidget);

    await tester.tap(find.text('24시'));
    await tester.pumpAndSettle();

    expect(find.text('24시 성수동물의료센터'), findsOneWidget);
    expect(find.text('행복한 동물병원'), findsNothing);
  });

  testWidgets('카테고리를 바꾸면 24시 토글이 꺼진다 — 켜 둔 채로 옮기면 "왜 안 나오지" 가 된다', (tester) async {
    await _pumpWide(tester);

    await tester.tap(find.text('동물병원').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('24시'));
    await tester.pumpAndSettle();
    expect(find.text('행복한 동물병원'), findsNothing);

    await tester.tap(find.text('여행지').first);
    await tester.pumpAndSettle();
    expect(find.text('24시'), findsNothing);

    await tester.tap(find.text('동물병원').first);
    await tester.pumpAndSettle();
    expect(find.text('행복한 동물병원'), findsOneWidget, reason: '다시 들어오면 토글은 꺼져 있다');
  });
}

// 지도 탭의 장소 카드 — 관광공사 사진이 있는 곳은 사진이 먼저, 카드 폭 (#449).
//
// 리스트 뷰만 세운다(지도 SDK 는 테스트에 없다). 테스트의 HTTP 는 사진을 못 받으므로
// `Image.network` 는 늘 errorBuilder 로 간다 — 그래서 "자리(16:9)가 있는가" 와
// "못 받았을 때 카드 폭의 카테고리 자리로 가는가" 를 여기서 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

const _photo = 'https://tong.visitkorea.or.kr/cms/resource/00/seoul-forest.jpg';

PetPlace _place(
  String id,
  String title, {
  String source = 'kto',
  String category = '',
  String contentTypeId = '',
  String image = '',
  String tel = '',
  double distM = 0,
}) =>
    PetPlace(
      contentId: id,
      title: title,
      source: source,
      category: category,
      contentTypeId: contentTypeId,
      addr: '서울특별시 성동구 뚝섬로 273',
      image: image,
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
      [
        _place('100', '서울숲', contentTypeId: '12', image: _photo, distM: 354),
        _place('vet:1', '성수 숲속 피부과 동물병원', source: 'vet', category: 'vet', tel: '02-123-4567', distM: 327),
      ];
}

Future<void> _pump(WidgetTester tester, {double width = 393, double height = 780, double textScale = 1}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ExploreScreen(repository: _FakeRepo()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('사진이 있는 곳은 사진이 먼저 — 카드 폭 · 16:9, 작은 섬네일이 아니다', (tester) async {
    await _pump(tester);

    final slot = find.byKey(const Key('place-photo-100'));
    expect(slot, findsOneWidget);
    expect(tester.widget<AspectRatio>(slot).aspectRatio, closeTo(16 / 9, 0.001));

    final cardWidth = tester.getSize(find.byKey(const Key('place-card-100'))).width;
    final slotSize = tester.getSize(slot);
    // 카드 테두리 1px 안쪽이 사진 폭이다.
    expect(slotSize.width, closeTo(cardWidth, 2), reason: '사진은 카드 폭을 다 쓴다');
    expect(slotSize.height, closeTo(slotSize.width * 9 / 16, 1));

    final image = tester.widget<Image>(find.descendant(of: slot, matching: find.byType(Image)));
    expect((image.image as NetworkImage).url, _photo);
    expect(find.byKey(const Key('place-thumb-100')), findsNothing, reason: '64 섬네일 자리는 사진 카드에 없다');
    expect(find.text('서울숲'), findsOneWidget);
    expect(find.text('서울특별시 성동구 뚝섬로 273'), findsNWidgets(2), reason: '주소는 두 카드 다 한 줄');
  });

  testWidgets('사진이 없는 곳(공공데이터 층)은 한 줄 카드 그대로 — 카테고리 아이콘 64', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('place-photo-vet:1')), findsNothing);
    final thumb = find.byKey(const Key('place-thumb-vet:1'));
    expect(thumb, findsOneWidget);
    expect(tester.getSize(thumb), const Size(64, 64));
    expect(find.descendant(of: thumb, matching: find.byType(Image)), findsNothing, reason: '사진이 없으니 부르지 않는다');
  });

  testWidgets('사진을 못 받으면 같은 자리에 카테고리색 바탕 — 목록이 흔들리지 않는다', (tester) async {
    await _pump(tester);

    // 테스트의 HTTP 는 400 을 준다 → errorBuilder.
    final fallback = find.byKey(const Key('place-photo-fallback-100'));
    expect(fallback, findsOneWidget);
    final slot = find.byKey(const Key('place-photo-100'));
    expect(tester.getSize(fallback), tester.getSize(slot), reason: '자리 크기가 그대로다');
  });

  testWidgets('시트 맨 위에 사진(16:9) — 사진 없는 곳의 시트엔 없다', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('서울숲'));
    await tester.pumpAndSettle();
    final photo = find.byKey(const Key('place-sheet-photo'));
    expect(photo, findsOneWidget);
    expect(tester.widget<AspectRatio>(photo).aspectRatio, closeTo(16 / 9, 0.001));
    expect(find.text('길찾기'), findsOneWidget, reason: '동작 줄은 그대로 아래에 있다');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('성수 숲속 피부과 동물병원'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place-sheet-photo')), findsNothing);
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('작은 화면 · 큰 글자에서 사진 시트가 넘치지 않고 스크롤된다', (tester) async {
    await _pump(tester, height: 480, textScale: 1.6);
    expect(tester.takeException(), isNull, reason: '큰 글자에서 목록 머리(개수 · 출처)가 넘치지 않는다');

    // 480dp 에서는 사진 카드의 이름이 화면 아래다 — 끌어올려서 누른다.
    await tester.ensureVisible(find.text('서울숲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서울숲'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('place-sheet-photo')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '사진 199dp 가 얹혀도 시트는 스크롤로 받는다');
    final scroll = find.ancestor(
        of: find.byKey(const Key('place-sheet-photo')), matching: find.byType(SingleChildScrollView));
    expect(scroll, findsOneWidget);
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('길찾기'), findsOneWidget);
  });
}

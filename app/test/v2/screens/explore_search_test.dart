// 지도의 검색 — 이슈 #620.
//
// 2026-09-17 실기기: 검색창에 글자가 안 써졌다. 버그가 아니라 **그 자리가 입력칸이
// 아니었다** — `Container` 안에 `Text` 하나였고 `TextField` 도 `onTap` 도 없었다.
// "아예 무용지물" 이라는 신고를 받았다.
//
// 찾는 일 자체는 처음부터 있었다(`PlaceCatalogRepository.search`, #338). 글쓰기·동네
// 고르기 화면이 이미 쓰고 있었고 **지도만 안 붙어 있었다.**
//
// 여기서 재는 것.
//   - 글자를 넣으면 **서버를 안 부르고** 결과가 뜬다
//   - 검색 중에는 칩 대신 검색어 하나 — 켜 둔 칩이 결과를 조용히 지우지 않는다
//   - 지우면 원래 목록으로 돌아온다
//   - 목록 뷰와 지도 뷰가 **같은 칸**이다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

PetPlace _place(String id, String title, {String contentTypeId = '12'}) => PetPlace(
      contentId: id,
      title: title,
      source: 'kto',
      category: '',
      contentTypeId: contentTypeId,
      addr: '서울특별시 성동구',
      image: '',
      tel: '',
      lat: 37.5445,
      lng: 127.0374,
      distM: 300,
    );

/// 주변 목록과 검색을 따로 답한다. **검색이 서버를 부르면 이 목이 안 불린다** — 그래서
/// `searchCalls` 가 0 이면 어딘가 다른 길로 갔다는 뜻이고, 그건 A안(#235) 위반이다.
class _FakeRepo extends PetPlacesRepository {
  _FakeRepo()
      : super(
          client: MockClient((req) async {
            throw StateError('검색은 서버를 부르면 안 된다: ${req.url}');
          }),
          baseUrl: 'http://unused',
        );

  int searchCalls = 0;
  String? lastQuery;

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async =>
      switch (contentTypeId) {
        'trail' => [_place('trail:1', '중랑천 산책로', contentTypeId: 'trail')],
        _ => [_place('100', '서울숲'), _place('101', '뚝섬한강공원')],
      };

  @override
  Future<List<PetPlace>> searchByName(String query, {int limit = 8}) async {
    searchCalls++;
    lastQuery = query;
    // 이름에 들어 있는 것만 — 진짜 저장소와 같은 규칙이다.
    return [
      for (final p in [_place('100', '서울숲'), _place('300', '서울숲 호수'), _place('101', '뚝섬한강공원')])
        if (p.title.contains(query)) p,
    ];
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('검색칸에 글자가 써지고, 결과가 목록을 바꾼다', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, ExploreScreen(repository: repo));

    expect(find.byKey(const Key('explore-search-field')), findsOneWidget,
        reason: '여기 있던 것은 Text 였다 — 눌러도 키보드가 안 올라왔다');

    await tester.enterText(find.byKey(const Key('explore-search-field')), '서울숲');
    await tester.pumpAndSettle();

    expect(repo.searchCalls, greaterThan(0));
    expect(repo.lastQuery, '서울숲');
    expect(find.text('서울숲'), findsWidgets);
    expect(find.text('서울숲 호수'), findsOneWidget);
    expect(find.text('뚝섬한강공원'), findsNothing, reason: '이름에 없는 곳은 빠진다');
    expect(find.textContaining('"서울숲" 검색 · 2곳'), findsOneWidget);
  });

  testWidgets('검색 중에는 칩 대신 검색어 하나 — 켜 둔 칩이 결과를 조용히 지우지 않는다', (tester) async {
    await _pump(tester, ExploreScreen(repository: _FakeRepo()));

    // 산책로 칩을 켠 채로 공원 이름을 찾는다. 칩이 그대로 걸려 있으면 0곳이 되고,
    // 사용자는 "그 이름이 없다" 고 읽는다 — 실제로는 칩이 가린 것이다.
    await tester.tap(find.text('산책로').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('explore-search-field')), '서울숲');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-search-chip')), findsOneWidget);
    expect(find.byKey(const Key('chip-trail')), findsNothing);
    expect(find.text('서울숲 호수'), findsOneWidget);
  });

  testWidgets('지우면 원래 목록으로 돌아온다 — 칩 줄도 함께', (tester) async {
    await _pump(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), '서울숲');
    await tester.pumpAndSettle();
    expect(find.text('뚝섬한강공원'), findsNothing);

    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-search-chip')), findsNothing);
    expect(find.byKey(const Key('chip-trail')), findsOneWidget);
    expect(find.text('뚝섬한강공원'), findsOneWidget, reason: '주변 목록이 돌아온다');
  });

  testWidgets('새 검색어를 치는 동안 옛 결과가 비치지 않는다', (tester) async {
    await _pump(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), '서울숲');
    await tester.pumpAndSettle();
    expect(find.text('서울숲 호수'), findsOneWidget);

    // **지우지 않고 바로 고쳐 친다.** 지우고 다시 치는 것보다 흔한 길이고, 이쪽이
    // 옛 결과를 들고 있다.
    //
    // 손이 멈추기를 220ms 기다렸다 찾는다. 그 사이에 화면이 뭘 보여 주는가가 여기서
    // 재는 것이다 — 옛 결과를 안 비우면 **새 검색어 밑에 지난 답이 깔린다.**
    await tester.enterText(find.byKey(const Key('explore-search-field')), '없는곳');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('서울숲 호수'), findsNothing,
        reason: '"없는곳" 을 치는데 "서울숲 호수" 가 보이면 화면이 거짓말을 한다');
    expect(find.byKey(const Key('explore-search-empty')), findsOneWidget);
    expect(find.text('찾는 중이에요'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('없는 이름이면 왜 없는지 말한다 — "다시 시도" 를 권하지 않는다', (tester) async {
    await _pump(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), '없는곳');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-search-empty')), findsOneWidget);
    expect(find.textContaining('반려동반이 되는 곳만'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing,
        reason: '몇 번을 눌러도 같은 답이 온다 — 권하면 안 된다');
  });

  testWidgets('목록에서 친 검색어가 지도 뷰에도 그대로 있다 — 같은 칸이다', (tester) async {
    await _pump(tester, ExploreScreen(repository: _FakeRepo()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), '서울숲');
    await tester.pumpAndSettle();

    // 지도 뷰로 전환. 지도 SDK 는 테스트에 없어 배경은 안 그려지지만 머리 줄은 선다.
    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('explore-map-search-field')));
    expect(field.controller!.text, '서울숲', reason: '뷰를 바꿨다고 검색어가 사라지면 안 된다');
    expect(find.byKey(const Key('explore-search-chip')), findsOneWidget);
  });
}

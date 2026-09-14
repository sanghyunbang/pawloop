// 지도 칩 줄 — 자주 쓰는 다섯이 먼저, 나머지는 "더보기" 뒤 (#449).
//
// 리스트 뷰만 세운다(지도 SDK 는 테스트에 없다). 칩 줄은 가로 ListView 라 보이는 것만 짓는다 —
// 넓은 화면(1600)에서 전부 보이게 두고 순서를 읽는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

class _FakeRepo extends PetPlacesRepository {
  final calls = <String?>[];

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
  }) async {
    calls.add(contentTypeId);
    return const [];
  }
}

Future<_FakeRepo> _pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = _FakeRepo();
  await tester.pumpWidget(MaterialApp(home: ExploreScreen(repository: repo)));
  await tester.pumpAndSettle();
  return repo;
}

/// 칩 줄의 글자를 왼쪽부터.
List<String> _labels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(const Key('chip-row')), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .toList();

const _primary = ['전체', '산책로', '동물병원', '카페·식당', '여행지', '놀이터'];
const _secondary = ['레포츠', '숙박', '쇼핑', '문화', '펫샵'];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('처음엔 자주 쓰는 다섯 + 더보기 — 산책로 · 동물병원 · 카페·식당이 앞이고 숙박 · 쇼핑은 숨어 있다', (tester) async {
    await _pumpWide(tester);

    expect(_labels(tester), [..._primary, '더보기']);
    for (final hidden in _secondary) {
      expect(find.text(hidden), findsNothing, reason: '$hidden 은 더보기 뒤다');
    }
  });

  testWidgets('더보기는 조회가 아니라 줄이다 — 펼치면 나머지 다섯 + 접기, 접으면 되돌아간다', (tester) async {
    final repo = await _pumpWide(tester);
    expect(repo.calls, [null]);

    await tester.tap(find.byKey(const Key('chip-more')));
    await tester.pumpAndSettle();
    expect(_labels(tester), [..._primary, ..._secondary, '접기']);
    expect(repo.calls, [null], reason: '펼치기는 조회를 안 한다');

    await tester.tap(find.byKey(const Key('chip-less')));
    await tester.pumpAndSettle();
    expect(_labels(tester), [..._primary, '더보기']);
    expect(repo.calls, [null]);
  });

  testWidgets('숨어 있던 칩을 고르면 그 키로 조회하고, 골라 둔 동안은 접히지 않는다 — 접기 칩도 없다', (tester) async {
    final repo = await _pumpWide(tester);

    await tester.tap(find.byKey(const Key('chip-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chip-32')));
    await tester.pumpAndSettle();

    expect(repo.calls, [null, '32'], reason: '숙박 칩 키로 다시 조회한다');
    expect(_labels(tester), [..._primary, ..._secondary], reason: '켜진 숙박이 보여야 하니 접기가 없다');
    expect(find.byKey(const Key('chip-less')), findsNothing);
    expect(find.byKey(const Key('chip-more')), findsNothing);

    // 전체로 돌아오면 다시 접을 수 있다.
    await tester.tap(find.byKey(const Key('chip-all')));
    await tester.pumpAndSettle();
    expect(repo.calls, [null, '32', null]);
    expect(find.byKey(const Key('chip-less')), findsOneWidget);
  });

  testWidgets('앞의 다섯은 kPetCategories 에 있는 키다 — 범례와 같은 색 · 아이콘을 쓴다', (tester) async {
    await _pumpWide(tester);
    for (final key in ['chip-trail', 'chip-vet', 'chip-39', 'chip-12', 'chip-playground']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });
}

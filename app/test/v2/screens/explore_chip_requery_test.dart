// 지도 화면의 칩이 조회에 붙는지 본다 — 이슈 #291 실측 후속.
//
// ## 왜 필요한가
//
// 에뮬레이터에서 병원 칩을 누르니 "이 지역엔 등록된 곳이 없어요" 였다. 서버는 같은 좌표로
// 1m 거리의 병원을 주는데도. 화면이 **칩 없이** 가까운 80곳을 받아 놓고 그 80곳 안에서
// 걸렀기 때문이다 — 서울시청 근처는 백화점 매장 80곳이 어느 병원보다 가깝다.
// 카탈로그·서버는 거른 뒤에 자르므로(`PlaceCatalogRepository.nearby` ·
// `PlaceQueryService.within`) 칩 키를 조회에 붙이기만 하면 된다. 이 테스트는 그 붙임과,
// 늦게 돌아온 옛 조회를 버리는 것을 잠근다.
//
// ## 왜 화면을 띄울 수 있나
//
// 목록 보기는 네이버 지도를 만들지 않는다. 현위치는 동의가 없으면 플러그인을 부르기 전에
// 비어서 돌아오고(`LocationService.locate`), 화면은 서울시청을 중심으로 둔다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

PetPlace _place(
  String id,
  String title, {
  String source = 'kto',
  String category = '',
  String contentTypeId = '',
}) =>
    PetPlace(
      contentId: id,
      title: title,
      source: source,
      category: category,
      contentTypeId: contentTypeId,
      addr: '서울특별시 중구',
      image: '',
      tel: '',
      lat: 37.5665,
      lng: 126.9816,
    );

/// 칩 키별로 다른 답을 주고, 무엇으로 불렸는지 적어 둔다.
class _FakeRepo extends PetPlacesRepository {
  _FakeRepo()
      : super(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://unused',
        );

  final calls = <String?>[];

  /// 칩 키별 지연 — 경합을 만들 때 쓴다.
  final delays = <String?, Duration>{};

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async {
    calls.add(contentTypeId);
    final delay = delays[contentTypeId];
    if (delay != null) await Future<void>.delayed(delay);
    return switch (contentTypeId) {
      'vet' => [_place('vet:1', '늘서울피부과동물병원', source: 'vet', category: 'vet')],
      'shop' => [_place('shop:1', '멍멍연구소', source: 'shop', category: 'shop')],
      _ => [
          _place('100', '프라다 롯데백화점 본점', contentTypeId: '38'),
          _place('101', '갤럭시 롯데백화점 본점', contentTypeId: '38'),
        ],
    };
  }
}

/// 칩 행은 카드보다 위에 있어 트리에서 먼저 온다 — 카드의 분류 배지도 같은 글자를 쓴다.
Finder _chip(String label) => find.text(label).first;

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  // 칩 아홉 개가 가로 스크롤 없이 다 보이게 넓힌다 — 지연 목록은 안 보이는 칩을 안 만든다.
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

  testWidgets('병원 칩을 누르면 칩 키로 다시 조회한다 — 받아 놓은 80곳 안에서 거르지 않는다',
      (tester) async {
    final repo = _FakeRepo();
    await _pumpWide(tester, ExploreScreen(repository: repo));

    expect(repo.calls, [null], reason: '첫 조회는 전체다');
    expect(find.text('프라다 롯데백화점 본점'), findsOneWidget);

    await tester.tap(_chip('동물병원'));
    await tester.pumpAndSettle();

    expect(repo.calls, [null, 'vet'], reason: '칩 키가 조회에 붙어야 한다 — 거른 뒤에 자르는 것은 저장소 몫이다');
    expect(find.text('늘서울피부과동물병원'), findsOneWidget);
    expect(find.text('프라다 롯데백화점 본점'), findsNothing);
    expect(find.text('이 지역엔 등록된 곳이 없어요'), findsNothing);

    await tester.tap(_chip('동물병원'));
    await tester.pumpAndSettle();
    expect(repo.calls, [null, 'vet'], reason: '켜진 칩을 다시 눌러도 조회하지 않는다');
  });

  testWidgets('늦게 돌아온 옛 조회는 버린다 — 병원을 눌렀다가 바로 펫샵을 누르면 펫샵이 남는다',
      (tester) async {
    final repo = _FakeRepo()..delays['vet'] = const Duration(seconds: 3);
    await _pumpWide(tester, ExploreScreen(repository: repo));

    await tester.tap(_chip('동물병원'));
    await tester.pump(); // 병원 조회가 떠 있다 — 3초 뒤에 돌아온다.
    // 펫샵은 "더보기" 뒤에 있다(#449) — 펼치는 것은 조회가 아니다.
    await tester.tap(find.byKey(const Key('chip-more')));
    await tester.pump();
    await tester.tap(_chip('펫샵'));
    await tester.pumpAndSettle();

    expect(find.text('멍멍연구소'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4)); // 이제 병원 조회가 돌아온다.
    await tester.pumpAndSettle();

    expect(find.text('멍멍연구소'), findsOneWidget,
        reason: '먼저 간 병원 조회가 늦게 돌아와도 펫샵 목록을 덮으면 안 된다');
    expect(find.text('늘서울피부과동물병원'), findsNothing);
    expect(repo.calls, [null, 'vet', 'shop']);
  });
}

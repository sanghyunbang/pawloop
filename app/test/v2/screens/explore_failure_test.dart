// 못 받은 것을 "없다" 고 말하지 않는다 — 이슈 #515.
//
// 저장소가 실패를 `const []` 로 돌려주던 동안 지도는 그것을 받아 **"이 지역엔 등록된 곳이
// 없어요"** 를 그렸다. 서버가 죽은 날에도 같은 문장이었다 — 사용자는 그 동네에 병원이
// 없다고 믿는다. `pet.dart` 가 커뮤니티 더미 앞에 적어 둔 문장이 그것이다: "화면이 서버를
// 못 불렀을 때 그릴 것은 빈 목록이 아니라 '불러오지 못했어요' 다."
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

/// 서버가 죽은 저장소. 몇 번 불렸는지 세어 "다시 시도" 가 진짜로 다시 부르는지 본다.
class _DeadRepo extends PetPlacesRepository {
  _DeadRepo({this.kind = PlaceFailureKind.network})
      : super(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://unused',
        );

  final PlaceFailureKind kind;
  int calls = 0;

  @override
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    String? contentTypeId,
  }) async {
    calls++;
    throw PlaceFailure(kind);
  }
}

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AuthState.resetForTest();
    LocationService.consented.value = false;
  });

  testWidgets('장소를 못 받으면 "못 받았어요" 와 다시 시도를 그린다 — "없어요" 가 아니다', (tester) async {
    AuthState.status.value = AuthStatus.unauthenticated;

    await _pumpWide(tester, ExploreScreen(repository: _DeadRepo()));

    expect(find.byKey(const Key('explore-places-failed')), findsOneWidget);
    expect(find.text('장소 목록을 못 받았어요'), findsOneWidget);
    expect(find.text('이 지역엔 등록된 곳이 없어요'), findsNothing,
        reason: '서버가 죽은 것을 "없다" 로 말하면 사용자는 그 동네에 병원이 없다고 믿는다');
  });

  testWidgets('이유마다 다른 문구다 — 429 를 "연결을 확인해 주세요" 라고 하지 않는다', (tester) async {
    AuthState.status.value = AuthStatus.unauthenticated;

    await _pumpWide(tester,
        ExploreScreen(repository: _DeadRepo(kind: PlaceFailureKind.rateLimited)));

    expect(find.text(PlaceFailureKind.rateLimited.message), findsOneWidget);
    expect(find.text(PlaceFailureKind.network.message), findsNothing);
  });

  testWidgets('"다시 시도" 는 진짜로 다시 부른다', (tester) async {
    AuthState.status.value = AuthStatus.unauthenticated;
    final repo = _DeadRepo();

    await _pumpWide(tester, ExploreScreen(repository: repo));
    final before = repo.calls;

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repo.calls, greaterThan(before),
        reason: '누르면 아무 일도 안 일어나는 버튼은 안내가 아니라 거짓말이다');
  });
}

// 지도 — 현위치를 못 받아 서울시청 기준일 때 그 말을 한다 (#324).
//
// 게스트는 동의 전이라 `LocationService.current()` 가 null 이고, 그때 목록은 중구
// 백화점부터였다. 왜 중구인지 화면이 말하지 않았다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

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
        PetPlace(
          contentId: '100',
          title: '프라다 롯데백화점 본점',
          source: 'kto',
          category: '',
          contentTypeId: '38',
          addr: '서울특별시 중구',
          image: '',
          tel: '',
          lat: 37.5665,
          lng: 126.9816,
        ),
      ];
}

Future<void> _pumpWide(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  // 지도가 내 동네를 기기에서 읽는다(#342). 목을 안 깔면 그 읽기가 안 끝나 화면이
  // 로딩에서 멈춘다 — pumpAndSettle 이 시간 초과로 죽는다.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AuthState.resetForTest);

  testWidgets('게스트(동의 전)에게 "서울시청 기준 · 로그인하고 위치를 켜면" 이 보인다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    LocationService.consented.value = false;

    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    expect(find.textContaining('서울시청 기준이에요'), findsOneWidget);
    expect(find.textContaining('로그인하고 위치를 켜면'), findsOneWidget);
  });

  testWidgets('로그인했지만 위치를 못 받으면 "위치 권한을 켜면" 이다', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationService.consented.value = false; // 동의 전이라 현위치가 null 이다

    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    expect(find.textContaining('위치 권한을 켜면'), findsOneWidget);
    expect(find.textContaining('로그인하고'), findsNothing);
  });

  testWidgets('동네를 골랐으면 서울시청이 아니라 그 동네 기준이라고 말한다 (#342)', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationService.consented.value = false;
    SharedPreferences.setMockInitialValues({
      'v2.neighborhood': '{"code":"1120068000","sigunguCode":"11200","sido":"서울특별시",'
          '"sigungu":"성동구","dong":"성수1가1동","lat":37.54554,"lng":127.04425}',
    });

    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));

    expect(find.textContaining('성수1가1동 기준이에요'), findsOneWidget);
    expect(find.textContaining('서울시청 기준'), findsNothing,
        reason: '고른 사람에게 "서울시청 기준" 은 틀린 말이고, 위치 권한을 켜러 갈 이유도 없다');
  });
}

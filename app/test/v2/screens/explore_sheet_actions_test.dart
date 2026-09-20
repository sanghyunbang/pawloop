// 지도 탐색 — 시트의 주 동작 · 산책로 머리와 먼 코스 안내 · 자리표시 카드 (#328).
//
// 리스트 뷰만 세운다(지도 SDK 는 테스트에 없다). 전화·길찾기는 `ExternalMaps.launcher` 를
// 갈아 끼워 어느 URI 를 열었는지 본다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:geolocator/geolocator.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/place_loop_repository.dart';
import 'package:heat_trip_flutter/v2/data/trail_route_repository.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart'
    show lastCourseLineForTest, lastDestinationForTest, trackingOpenerForTest;

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

/// 산책로 경로를 서버 대신 답한다 — 계약의 `TrailRoute` 모양 그대로다.
///
/// 목의 키를 앱이 읽는 키로 만들면 앱이 틀린 키를 읽고 있을 때 테스트가 그 버그에
/// 동의한다(#82). 그래서 `points`·`waypoints` 를 계약에서 가져왔다.
class _FakeTrails extends TrailRouteRepository {
  _FakeTrails()
      : super(
          client: MockClient((req) async {
            // 동네 길(lt…)은 선이 없고 경유지만, 두루누비는 선만 — 서버가 그렇게 답한다.
            final body = req.url.path.contains('/trails/lt')
                ? '{"courseId":"lt9766bc9af8","name":"3.1운동길B","lengthM":4200,"pointCount":0,'
                    '"points":[],"waypoints":["보신각","보성사 터","탑골공원"]}'
                : '{"courseId":"trail:41","name":"DMZ 평화의 길 4-1코스","lengthM":17553,'
                    '"pointCount":3,"points":[[126.82,37.59],[126.83,37.60],[126.84,37.61]],'
                    '"waypoints":[]}';
            return http.Response.bytes(utf8.encode(body), 200,
                headers: {'content-type': 'application/json'});
          }),
          baseUrl: 'http://unused',
        );
}

/// 경유지가 **열한 곳**인 코스 — 2026-09-17 에 사장님 화면에 뜬 그 코스다.
///
/// 조각 수는 코스마다 1~51 로 크게 다르다. 많은 쪽으로 재지 않으면 "버튼이 밀린다" 를
/// 영영 못 본다 — 세 곳짜리로는 밀리지 않는다.
class _FakeTrailsMany extends TrailRouteRepository {
  _FakeTrailsMany()
      : super(
          client: MockClient((req) async {
            const stops = '["쌍문역","노해파출소 터","노해면사무소 자리","방학천교","모랫말터",'
                '"천주교 도봉동성당","성황당 터","무수천교","서원내교","누원터","도봉산역"]';
            final body = '{"courseId":"lt9766bc9af8","name":"3.1운동길B","lengthM":5500,'
                '"pointCount":0,"points":[],"waypoints":$stops}';
            return http.Response.bytes(utf8.encode(body), 200,
                headers: {'content-type': 'application/json'});
          }),
          baseUrl: 'http://unused',
        );
}

/// 추천 코스(#725)를 서버 대신 답한다 — 계약의 `PlaceLoop` 모양 그대로, 어느 장소·길이에도 세 점 고리.
class _FakeLoops extends PlaceLoopRepository {
  _FakeLoops()
      : super(
          client: MockClient((req) async {
            final id = Uri.decodeComponent(req.url.pathSegments[2]);
            final body = '{"contentId":"$id","targetM":2000,"available":true,"reason":null,'
                '"distanceM":2130,"durationS":1704,"pointCount":3,'
                '"points":[[126.82,37.59],[126.83,37.60],[126.82,37.59]]}';
            return http.Response.bytes(utf8.encode(body), 200,
                headers: {'content-type': 'application/json'});
          }),
          baseUrl: 'http://unused',
        );
}

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
            // 동네 길(#346) — 관리기관 전화번호가 있고 선이 없다.
            _place('trail:lt9766bc9af8', '3.1운동길B',
                source: 'trail', category: 'trail', tel: '02-2148-1855', distM: 407),
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

Future<void> _pumpWide(WidgetTester tester, Widget child, {double? width}) async {
  tester.view.physicalSize = width == null ? const Size(1600, 1200) : Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = width == null ? 1.0 : 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  // 지도가 내 동네를 기기에서 읽는다(#342). 목을 안 깔면 그 읽기가 안 끝나
  // 화면이 멈춘다 — pumpAndSettle 이 시간 초과로 죽는다.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final original = ExternalMaps.launcher;
  final originalCanOpen = ExternalMaps.canOpen;
  // 네이버 지도가 "있다" 고 답하는 기기로 둔다 — 안 그러면 길찾기가 웹으로 간다(2026-09-21).
  setUp(() => ExternalMaps.canOpen = (_) async => true);
  tearDown(() {
    ExternalMaps.launcher = original;
    ExternalMaps.canOpen = originalCanOpen;
  });

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

    expect(find.textContaining('가까운 산책로 · 2곳'), findsOneWidget);
    expect(find.textContaining('반려동반 가능 ·'), findsNothing);
    // 첫 항목이 407m 라 먼 코스 안내는 없다 — 목록은 거리순이다(#321).
    expect(find.textContaining('가장 가까운 코스는'), findsNothing);

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

  // 이 자리에는 '동네 길 시트에는 "지도에서 보기" 가 없다' 는 검사가 있었다. 그 판단의
  // 근거("그릴 선이 없다")는 맞았지만, 결과는 **누를 것이 하나도 없는 시트**였다 —
  // 2026-09-17 에 사장님이 "저렇게 해놓으면 어쩌라는 거지" 라고 신고했다(#619).
  // 선이 없어도 할 일이 있다: 지도를 시작 지점으로 옮기고, 거쳐 가는 곳 이름을 보여 준다.
  testWidgets('동네 길 시트에도 "지도에서 보기" 가 있다 — 선이 없어도 어디인지는 보여 준다 (#619)', (tester) async {
    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrails()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    expect(find.text('지도에서 보기'), findsOneWidget);
    expect(find.text('전화'), findsOneWidget, reason: '관리기관 전화번호는 있다');
    expect(find.text('이 코스 걷기'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(find.text('동네 길 · 지자체(공공데이터포털)'), findsOneWidget,
        reason: '두루누비라고 적으면 출처가 거짓이다');
  });

  testWidgets('동네 길 시트가 거쳐 가는 곳을 보여 주고, 선이 없다는 것을 말한다 (#619)', (tester) async {
    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrails()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trail-no-line-note')), findsOneWidget,
        reason: '4.2km 라고 적어 놓고 점 하나만 찍으면 고장 난 줄 안다');
    expect(find.text('거쳐 가는 곳 3곳'), findsOneWidget);
    expect(find.text('보신각'), findsOneWidget);
    expect(find.text('보성사 터'), findsOneWidget);
    expect(find.text('탑골공원'), findsOneWidget);

    // 한 줄로 흘리면 말줄임에 걸려 반쪽 이름이 남는다 — 조각마다 칸을 준다.
    final wrap = tester.widget<Wrap>(find.byKey(const Key('trail-waypoints')));
    expect(wrap.children, hasLength(3));
  });

  testWidgets('경유지가 열한 곳이어도 "지도에서 보기" 가 화면 안에 있다 (#619)', (tester) async {
    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrailsMany()),
        width: 393);
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    expect(find.text('거쳐 가는 곳 11곳'), findsOneWidget);

    // 시트는 스크롤되니 버튼이 "없는" 것은 아니다. 그런데 찾아서 내려야 보이는 버튼은
    // 없는 것과 비슷하다 — 사장님이 "지도로 넘어갈 수가 없다" 고 했다(2026-09-17).
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final button = tester.getRect(find.byKey(const Key('place-action-지도에서 보기')));
    expect(button.bottom, lessThanOrEqualTo(screen),
        reason: '버튼이 화면 아래로 밀렸다 — 경유지 목록을 버튼 위에 두면 이렇게 된다');
  });

  testWidgets('시트 순서: 안내 한 줄 → 버튼 → 경유지 목록 (#619)', (tester) async {
    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrailsMany()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    final note = tester.getRect(find.byKey(const Key('trail-no-line-note'))).top;
    final button = tester.getRect(find.byKey(const Key('place-action-지도에서 보기'))).top;
    final stops = tester.getRect(find.byKey(const Key('trail-waypoints'))).top;

    expect(note, lessThan(button),
        reason: '"시작 지점만 표시돼요" 는 거리·시간 바로 밑이어야 한다 — 오해가 거기서 생긴다');
    expect(button, lessThan(stops),
        reason: '누를 것이 먼저, 읽을 것이 나중이다 — 조각 수가 코스마다 1~51 로 다르다');
  });

  testWidgets('지도 시트의 "이 코스 걷기" 도 멀어도 우리 추적 화면을 연다 — 홈 카드와 같게 (#623 · 2026-09-21)',
      (tester) async {
    // 같은 이름의 버튼이 두 곳에서 다른 일을 하면 안 된다 — 홈 시트와 같은 startWalk 를 지나
    // 같은 목적지를 들고 간다. #724 의 "멀면 묻는다" 는 지웠다.
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
    addTearDown(() {
      AuthState.resetForTest();
      LocationPriming.resetForTest();
      trackingOpenerForTest = null;
    });

    var opened = 0;
    trackingOpenerForTest = (_, __, place) async {
      opened++;
      expect(place?.title, 'DMZ 평화의 길 4-1코스');
    };
    lastDestinationForTest = null;

    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrails(), loops: _FakeLoops()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();
    // 19.8km 짜리 두루누비 — 멀어도 연다.
    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 코스 걷기'));
    await tester.pumpAndSettle();

    expect(opened, 1, reason: '멀다고 지도 앱으로 넘기지 않는다 — 우리 추적 화면이다');
    final asked = lastDestinationForTest;
    expect(asked, isNotNull, reason: '추적 화면이 "코스 시작점까지 N km" 를 적을 재료');
    expect(asked!.lat, 37.5445);
    expect(asked.lng, 127.0374);
    expect(asked.distanceM, 19800, reason: '목록에 뜬 거리를 그대로 들고 가야 한다');
  });

  testWidgets('지도 탭 장소 시트에도 추천 코스가 있다 — 받은 선을 그리고, "이 코스 걷기" 가 그 선을 들고 간다 (#725)',
      (tester) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
    addTearDown(() {
      AuthState.resetForTest();
      LocationPriming.resetForTest();
      trackingOpenerForTest = null;
    });
    // 추적 화면 대신 빈 함수 — 재는 것은 "선이 startWalk 까지 오는가" 다.
    trackingOpenerForTest = (_, __, ___) async {};
    lastCourseLineForTest = null;

    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrails(), loops: _FakeLoops()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();

    expect(find.text('추천 코스'), findsOneWidget, reason: 'PR #753 이 "다음 조각" 으로 남긴 자리 — 홈 시트와 같은 줄');
    expect(find.byKey(const Key('loop-len-2000')), findsOneWidget);
    expect(find.textContaining('실제 2.1km · 약 28분'), findsOneWidget);
    expect(find.byKey(const Key('loop-preview')), findsOneWidget, reason: '걷기 전에 우리 화면에 그린다(키 없는 검사는 캔버스)');
    expect(find.byKey(const Key('place-posts-link')), findsOneWidget,
        reason: '홈 시트에만 있던 "이 장소의 글 보기" 를 탐색 탭 시트에도(2026-09-21 사장님)');

    await tester.tap(find.text('이 코스 걷기'));
    await tester.pumpAndSettle();

    expect(lastCourseLineForTest, isNotNull, reason: '시트가 받은 선이 startWalk 까지 와야 추적 화면이 깐다');
    expect(lastCourseLineForTest, hasLength(3));
    expect(lastCourseLineForTest!.first, [126.82, 37.59]);
  });

  testWidgets('병원 시트에는 추천 코스가 없다 — 걸을 곳이 아니다', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo(), loops: _FakeLoops()));
    await tester.tap(find.text('성수 숲속 피부과 동물병원'));
    await tester.pumpAndSettle();

    expect(find.text('추천 코스'), findsNothing);
    expect(find.text('이 코스 걷기'), findsNothing);
  });

  testWidgets('두루누비 시트에는 그대로 "지도에서 보기" 가 있고, 경유지 칸은 안 쓴다', (tester) async {
    await _pumpWide(tester,
        ExploreScreen(repository: _FakeRepo(), trailRoutes: _FakeTrails()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DMZ 평화의 길 4-1코스'));
    await tester.pumpAndSettle();

    expect(find.text('지도에서 보기'), findsOneWidget);
    expect(find.text('걷기여행길 · 두루누비(한국관광공사)'), findsOneWidget);
    // 지도에 그려진 선이 이미 어디로 가는지 말한다 — 같은 말을 이름으로 또 적지 않는다.
    expect(find.byKey(const Key('trail-waypoints')), findsNothing);
    expect(find.byKey(const Key('trail-no-line-note')), findsNothing);
  });

  testWidgets('버튼이 넷이어도 393dp 에서 안 넘친다 — 자르지 않고 줄여 넣는다', (tester) async {
    // 칩까지는 넓은 화면에서 간다 — 393dp 에서는 칩 줄이 가로로 잘려 '산책로' 가
    // 아직 만들어지지도 않는다(가로 ListView 는 보이는 것만 짓는다).
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    // 시트를 열기 직전에만 좁힌다. 시트는 화면 폭을 그대로 쓴다.
    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    expect(find.text('이 코스 걷기'), findsOneWidget);
    expect(find.text('전화'), findsOneWidget);
    expect(find.text('길찾기'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '동네 길은 전화번호가 있어 버튼이 하나 더 선다 — 393dp 에서 28px 넘쳤다');
  });

  testWidgets('버튼 여백이 셋 다 같다 — 긴 이름만 모서리에 닿으면 안 된다 (#535)', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    /// 칸의 왼쪽 끝부터 아이콘까지 · 글자 끝부터 칸의 오른쪽 끝까지.
    ({double left, double right}) padding(String label) {
      final box = find.byKey(Key('place-action-$label'));
      expect(box, findsOneWidget, reason: '$label 칸을 못 찾았다');
      final outer = tester.getRect(box);
      final icon = tester.getRect(find.descendant(of: box, matching: find.byType(Icon)));
      final text = tester.getRect(find.descendant(of: box, matching: find.byType(Text)));
      return (left: icon.left - outer.left, right: outer.right - text.right);
    }

    // 동네 길은 버튼이 넷이라 393dp 에서 **두 줄**이 된다(#619). 여백을 견주는 것은
    // 같은 줄에 선 칸끼리다 — 줄이 다르면 남는 자리가 달라 값도 다른 게 맞다.
    double rowOf(String label) => tester.getRect(find.byKey(Key('place-action-$label'))).top;

    const labels = ['이 코스 걷기', '전화', '길찾기', '지도에서 보기'];
    final pads = {for (final l in labels) l: padding(l)};

    for (final e in pads.entries) {
      expect(e.value.left, greaterThan(4),
          reason: '${e.key} 의 글자가 모서리에 닿는다 — 폭을 똑같이 나누면 긴 이름부터 그렇게 된다');
      expect(e.value.left, closeTo(e.value.right, 1.0),
          reason: '${e.key} 의 좌우가 다르다');
    }

    final rows = <double, List<String>>{};
    for (final l in labels) {
      rows.putIfAbsent(rowOf(l), () => []).add(l);
    }
    expect(rows, hasLength(2), reason: '넷을 한 줄에 욱여넣으면 글자가 모서리에 닿는다 (#535)');

    for (final row in rows.values) {
      final first = pads[row.first]!.left;
      for (final l in row) {
        expect(pads[l]!.left, closeTo(first, 1.0),
            reason: '한 줄에 선 칸들의 여백이 서로 다르면 한 칸만 꽉 차 보인다 — '
                '지금 ${{for (final k in row) k: pads[k]!.left.toStringAsFixed(1)}}');
      }
    }
  });

  testWidgets('이름이 길면 칸도 넓다 — 폭을 똑같이 나누지 않는다 (#535)', (tester) async {
    await _pumpWide(tester, ExploreScreen(repository: _FakeRepo()));
    await tester.tap(_chip('산책로'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(393 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('3.1운동길B'));
    await tester.pumpAndSettle();

    double widthOf(String label) => tester.getSize(find.byKey(Key('place-action-$label'))).width;

    expect(widthOf('이 코스 걷기'), greaterThan(widthOf('길찾기')));
    expect(widthOf('길찾기'), greaterThan(widthOf('전화')),
        reason: '세 글자가 두 글자보다 넓어야 한다 — 같으면 폭을 n등분하고 있는 것이다');
  });
}

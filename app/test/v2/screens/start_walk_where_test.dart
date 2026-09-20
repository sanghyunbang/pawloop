// 코스가 멀어도 **우리 추적 화면에서 시작한다** — 이슈 #623 → #724 → 2026-09-21 사장님 결정.
//
// #724 는 멀면 "N km 떨어져 있어요" 를 말하고 지도 앱으로 길 안내만 내밀었다. 사장님이 폰에서
// "'이 코스 걷기' 하면 네이버 지도로 가는 게 아니라 내 앱의 산책 시작 화면이 켜져야 한다" 고 했다 —
// 우리 앱의 값은 우리 추적이고, 그 길로 가면 우리 앱은 네이버로 가는 통로일 뿐이다. 그래서 거리로
// 가르던 자리를 지웠다. 목적지는 추적 화면이 "코스 시작점까지 N km" 를 적는 데만 쓴다.
//
// 여기서 재는 것.
//   - 멀어도(2.4km · 325km) 추적 화면이 열린다 — 지도 앱은 안 연다
//   - 목적지·코스 선이 그대로 추적 화면까지 간다
//   - 가까워도 · 거리를 몰라도 · 목적지가 없어도 연다
//   - 후보 반경 상수 셋이 서로 맞는다(2km 먼저 · 5km 까지)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/course_candidates.dart';
import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart' show WalkPlaceRef;
import 'package:heat_trip_flutter/v2/domain/course_recommender.dart';
import 'package:heat_trip_flutter/v2/domain/walk_destination.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart';

const _place = WalkPlaceRef(title: '등나무근린공원', source: 'kto', contentId: '100');
const _far = WalkDestination(lat: 37.6447, lng: 127.0654, distanceM: 2400);
const _veryFar = WalkDestination(lat: 35.1796, lng: 129.0756, distanceM: 325000);
const _near = WalkDestination(lat: 37.6447, lng: 127.0654, distanceM: 120);
const _unknown = WalkDestination(lat: 37.6447, lng: 127.0654);
const _line = [
  [127.0654, 37.6447],
  [127.0680, 37.6460],
  [127.0654, 37.6447],
];

/// 홈 카드의 "이 코스 걷기" 자리. 추적 화면 대신 세는 함수를 꽂는다.
Future<int Function()> _pump(WidgetTester t, {WalkDestination? destination = _far}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  var opened = 0;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => startWalk(
            ctx,
            place: _place,
            destination: destination,
            courseLine: _line,
            // 이 검사에서 재는 것은 "거리와 상관없이 여는가" 하나다. 뒤따르는 물음들(강아지·권한)이
            // 끼어들면 무엇 때문에 안 열렸는지 못 가른다 — 권한은 이미 있다고 둔다.
            openTracking: (_, __, ___) async => opened++,
          ),
          child: const Text('이 코스 걷기'),
        ),
      ),
    ),
  ));
  return () => opened;
}

void main() {
  late List<Uri> opened;
  final originalLauncher = ExternalMaps.launcher;
  final originalCanOpen = ExternalMaps.canOpen;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
    opened = [];
    ExternalMaps.canOpen = (_) async => true;
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
    lastDestinationForTest = null;
    lastCourseLineForTest = null;
  });

  tearDown(() {
    AuthState.resetForTest();
    LocationPriming.resetForTest();
    ExternalMaps.launcher = originalLauncher;
    ExternalMaps.canOpen = originalCanOpen;
  });

  testWidgets('2.4km 멀어도 우리 추적 화면이 열린다 — 지도 앱은 안 연다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(count(), 1, reason: '2026-09-21 — "멀면 지도 앱으로" 를 지웠다. 우리 앱의 값은 우리 추적이다');
    expect(opened, isEmpty, reason: '네이버 지도로 넘기지 않는다');
    expect(find.textContaining('떨어져 있어요'), findsNothing, reason: '막는 시트가 없다');
  });

  testWidgets('325km(부산)여도 연다 — 어디서 걷기 시작할지는 걷는 사람이 정한다', (t) async {
    final count = await _pump(t, destination: _veryFar);
    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();
    expect(count(), 1);
    expect(opened, isEmpty);
  });

  testWidgets('목적지와 코스 선이 추적 화면까지 간다 — "코스 시작점까지 N km" 와 지도 선의 재료', (t) async {
    await _pump(t);
    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(lastDestinationForTest, isNotNull);
    expect(lastDestinationForTest!.distanceM, 2400);
    expect(lastDestinationForTest!.label, '2.4km');
    expect(lastCourseLineForTest, hasLength(3));
  });

  testWidgets('가까워도 · 거리를 몰라도 · 목적지가 없어도 연다', (t) async {
    for (final dest in [_near, _unknown, null]) {
      final count = await _pump(t, destination: dest);
      await t.tap(find.text('이 코스 걷기'));
      await t.pumpAndSettle();
      expect(count(), 1, reason: '목적지 $dest');
    }
    expect(opened, isEmpty);
  });

  test('후보 반경 상수 셋 — 2km 를 먼저 보고(카드 · 추천기), 없으면 5km 까지(카드 · 추천기)', () {
    expect(CourseCandidates.radiusM, 2000);
    expect(CourseRecommender.walkRadiusM, CourseCandidates.radiusM,
        reason: '카드가 먼저 찾는 반경과 추천기의 "걸어서 가는" 반경이 다르면 카드가 내민 코스를 추천기가 버린다');
    expect(CourseRecommender.maxDistanceM, CourseCandidates.widenRadiusM,
        reason: '2km 에 없어 5km 까지 넓힌 후보를 추천기가 도로 버리면 카드는 여전히 빈다');
  });
}

// 코스가 멀면 **시작하지 않고** "N km 떨어져 있어요" 를 말한다 — 이슈 #623 → #724.
//
// #623 은 "어디서 시작할까요?" 를 물었고 "지금 여기서" 가 있었다. 거리는 보여 주기만 하고
// 분기에 안 써서, 부산 코스를 서울에서 시작할 수 있었다. 2026-09-20 사장님 결정으로
// "여기서" 를 지웠다 — 기준(`WalkDestination.nearM`) 안이면 묻지 않고 바로 시작, 밖이면
// 길 안내만.
//
// 여기서 재는 것.
//   - 멀면 시트가 뜨고 **"여기서" 가 없다** — 시작 횟수 0
//   - "지도 앱으로 길 안내" 는 지도 앱을 열고 **추적을 안 연다**
//   - 가까우면 시트 없이 **바로 연다** — 경계값 2km 는 안, 2,001m 는 밖. 홈 카드가 후보를 고르는
//     반지름과 같은 값이다(2026-09-21 — 300m 였을 때는 카드가 내민 코스를 늘 막았다)
//   - 거리를 모르면 시작하지 않는다
//   - 닫으면 **아무것도 안 한다** — 실수로 눌렀을 때 30분짜리 기록이 시작되면 안 된다
//   - 목적지가 없으면 예전처럼 바로 시작한다
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
import 'package:heat_trip_flutter/v2/screens/walk_start_point_sheet.dart';

const _place = WalkPlaceRef(title: '등나무근린공원', source: 'kto', contentId: '100');
const _far = WalkDestination(lat: 37.6447, lng: 127.0654, distanceM: 2400);
const _near = WalkDestination(lat: 37.6447, lng: 127.0654, distanceM: 120);
const _unknown = WalkDestination(lat: 37.6447, lng: 127.0654);

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
            // 이 검사에서 재는 것은 "거리로 가르기" 하나다. 뒤따르는 물음들(강아지·권한)이
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
    // 네이버 지도가 "있다" 고 답하는 기기로 둔다 — 안 그러면 길 안내가 웹으로 간다(2026-09-21).
    ExternalMaps.canOpen = (_) async => true;
    ExternalMaps.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  tearDown(() {
    AuthState.resetForTest();
    LocationPriming.resetForTest();
    WalkStartPointSheet.resetForTest();
    ExternalMaps.launcher = originalLauncher;
    ExternalMaps.canOpen = originalCanOpen;
  });

  testWidgets('멀면 "N m 떨어져 있어요" 가 뜨고 "여기서" 는 없다 — 시작하지 않는다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('walk-start-point-title')), findsOneWidget);
    expect(find.text('2.4km 떨어져 있어요'), findsOneWidget,
        reason: '카드가 보여 준 거리가 곧 시작하지 않는 이유다 — 여기서도 말해야 한다');
    expect(find.text('등나무근린공원에 도착하면 홈에서 산책을 시작해 주세요'), findsOneWidget);
    expect(find.byKey(const Key('walk-start-directions')), findsOneWidget);
    expect(find.byKey(const Key('walk-start-here')), findsNothing,
        reason: '#724 — 멀리 있는 코스를 지금 자리에서 시작하는 길이 없어야 한다');
    expect(count(), 0);
  });

  testWidgets('"지도 앱으로 길 안내" 는 지도 앱을 열고 추적은 시작하지 않는다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('walk-start-directions')));
    await t.pumpAndSettle();

    expect(opened, isNotEmpty);
    expect(opened.first.scheme, 'nmap', reason: '네이버 지도 앱을 먼저 시도한다');
    expect(opened.first.queryParameters['dname'], '등나무근린공원');
    expect(count(), 0, reason: '거기 가서 시작할 것이다 — 지금 걷기 시작하면 안 된다');
  });

  testWidgets('가까우면 묻지 않고 바로 연다', (t) async {
    final count = await _pump(t, destination: _near);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('walk-start-point-title')), findsNothing);
    expect(count(), 1);
    expect(opened, isEmpty, reason: '지도 앱을 열 이유가 없다');
  });

  testWidgets('경계 — 2km 는 안, 2,001m 는 밖. 홈 카드의 후보 반지름과 같은 값이다', (t) async {
    expect(WalkDestination.nearM, 2000);
    expect(WalkDestination.nearM, CourseRecommender.maxDistanceM,
        reason: '카드가 "걸어서 가는 거리" 라며 내민 코스를 시작에서 막으면 앞뒤가 안 맞는다');
    expect(WalkDestination.nearM, CourseCandidates.radiusM);
    expect(const WalkDestination(lat: 0, lng: 0, distanceM: 2000).isNear, isTrue);
    expect(const WalkDestination(lat: 0, lng: 0, distanceM: 2001).isNear, isFalse);
    expect(const WalkDestination(lat: 0, lng: 0, distanceM: 0).isNear, isTrue);
    expect(const WalkDestination(lat: 0, lng: 0).isNear, isFalse,
        reason: '거리를 모르면 가깝다고 치지 않는다');

    final count = await _pump(t, destination: const WalkDestination(lat: 37.6, lng: 127.0, distanceM: 2001));
    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('walk-start-point-title')), findsOneWidget);
    expect(count(), 0);
  });

  testWidgets('거리를 모르면 시작하지 않고 그렇게 말한다', (t) async {
    final count = await _pump(t, destination: _unknown);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(find.text('거리를 알 수 없어요'), findsOneWidget);
    expect(find.byKey(const Key('walk-start-here')), findsNothing);
    expect(count(), 0);
  });

  testWidgets('시트를 닫으면 아무것도 안 한다 — 실수로 눌러도 기록이 안 시작된다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('walk-start-close')));
    await t.pumpAndSettle();

    expect(count(), 0);
    expect(opened, isEmpty);
  });

  testWidgets('목적지가 없으면 안 묻는다 — 홈의 큰 "산책 시작" 은 갈 곳이 없다', (t) async {
    final count = await _pump(t, destination: null);

    await t.tap(find.text('이 코스 걷기'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('walk-start-point-title')), findsNothing);
    expect(count(), 1, reason: '물을 것이 없으면 예전처럼 바로 시작한다');
  });
}

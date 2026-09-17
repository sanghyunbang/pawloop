// 멀리 있는 코스에서 "산책 시작" 을 누르면 **어디서 시작할지 묻는다** — 이슈 #623.
//
// 예전에는 안 물었다. `등나무근린공원 · 450m 거리` 를 보여 주고 버튼을 누르면 지금 서 있는
// 자리에서 추적이 시작됐고, 코스 이름은 기록에 붙는 꼬리표였다. 목표 1.0km 에 가는 450m 가
// 먹히고, 거기 안 갔어도 기록에는 그 이름이 남았다.
//
// 여기서 재는 것 넷.
//   - 목적지를 들고 오면 **묻는다**
//   - "길 안내" 는 지도 앱을 열고 **추적을 안 연다**
//   - "지금 여기서 시작" 은 예전처럼 연다
//   - 닫으면 **아무것도 안 한다** — 실수로 눌렀을 때 30분짜리 기록이 시작되면 안 된다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/external_maps.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart' show WalkPlaceRef;
import 'package:heat_trip_flutter/v2/domain/walk_destination.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart';
import 'package:heat_trip_flutter/v2/screens/walk_start_point_sheet.dart';

const _place = WalkPlaceRef(title: '등나무근린공원', source: 'kto', contentId: '100');
const _far = WalkDestination(lat: 37.6447, lng: 127.0654, distanceM: 450);

/// 홈 카드의 "여기서 산책 시작" 자리. 추적 화면 대신 세는 함수를 꽂는다.
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
            // 이 검사에서 재는 것은 "어디서 시작할지" 하나다. 뒤따르는 물음들(강아지·권한)이
            // 끼어들면 무엇 때문에 안 열렸는지 못 가른다 — 권한은 이미 있다고 둔다.
            openTracking: (_, __, ___) async => opened++,
          ),
          child: const Text('여기서 산책 시작'),
        ),
      ),
    ),
  ));
  return () => opened;
}

void main() {
  late List<Uri> opened;
  final originalLauncher = ExternalMaps.launcher;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
    opened = [];
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
  });

  testWidgets('목적지를 들고 오면 어디서 시작할지 묻는다 — 거리를 함께 말한다', (t) async {
    await _pump(t);

    await t.tap(find.text('여기서 산책 시작'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('walk-start-point-title')), findsOneWidget);
    expect(find.text('등나무근린공원까지 450m 예요'), findsOneWidget,
        reason: '거리를 카드가 보여 줬으면 여기서도 말해야 한다 — 그 거리가 이 물음의 이유다');
    expect(find.byKey(const Key('walk-start-directions')), findsOneWidget);
    expect(find.byKey(const Key('walk-start-here')), findsOneWidget);
  });

  testWidgets('"길 안내" 는 지도 앱을 열고 추적은 시작하지 않는다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('여기서 산책 시작'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('walk-start-directions')));
    await t.pumpAndSettle();

    expect(opened, isNotEmpty);
    expect(opened.first.scheme, 'nmap', reason: '네이버 지도 앱을 먼저 시도한다');
    expect(opened.first.queryParameters['dname'], '등나무근린공원');
    expect(count(), 0, reason: '거기 가서 시작할 것이다 — 지금 걷기 시작하면 안 된다');
  });

  testWidgets('"지금 여기서 시작" 은 예전처럼 추적을 연다', (t) async {
    final count = await _pump(t);

    await t.tap(find.text('여기서 산책 시작'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('walk-start-here')));
    await t.pumpAndSettle();

    expect(count(), 1);
    expect(opened, isEmpty, reason: '지도 앱을 열 이유가 없다');
  });

  testWidgets('시트를 닫으면 아무것도 안 한다 — 실수로 눌러도 기록이 안 시작된다', (t) async {
    WalkStartPointSheet.ask = (_, __, ___) async => null;
    final count = await _pump(t);

    await t.tap(find.text('여기서 산책 시작'));
    await t.pumpAndSettle();

    expect(count(), 0);
    expect(opened, isEmpty);
  });

  testWidgets('목적지가 없으면 안 묻는다 — 홈의 큰 "산책 시작" 은 갈 곳이 없다', (t) async {
    final count = await _pump(t, destination: null);

    await t.tap(find.text('여기서 산책 시작'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('walk-start-point-title')), findsNothing);
    expect(count(), 1, reason: '물을 것이 없으면 예전처럼 바로 시작한다');
  });
}

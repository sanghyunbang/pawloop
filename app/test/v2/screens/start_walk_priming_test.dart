// 첫 산책 시작 앞의 위치 사전 안내 — "허용하기" 전에는 권한을 묻는 화면을 열지 않는다 (#325).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/screens/location_priming_sheet.dart';
import 'package:heat_trip_flutter/v2/screens/start_walk.dart';

/// 홈의 "산책 시작" 자리. 추적 화면(권한을 실제로 묻는 곳) 대신 세는 함수를 꽂는다.
Future<int Function()> _pump(WidgetTester t) async {
  // 1080×2400 기기(DPR 2.625) — 시트가 실제 폰 높이에서 그려지는지 본다.
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  var opened = 0;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => startWalk(ctx, openTracking: (_) async => opened++),
          child: const Text('산책 시작'),
        ),
      ),
    ),
  ));
  return () => opened;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(() {
    AuthState.resetForTest();
    LocationPriming.resetForTest();
  });

  testWidgets('아직 물어본 적 없으면 시트가 먼저 뜨고, "허용하기" 전에는 추적 화면을 열지 않는다', (t) async {
    LocationPriming.checkPermission = () async => LocationPermission.denied;
    final opened = await _pump(t);

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();

    expect(find.text('산책 경로를 그리려면 위치가 필요해요'), findsOneWidget);
    expect(find.text('프로필에서 언제든 끌 수 있어요'), findsOneWidget);
    expect(find.text('허용하기'), findsOneWidget);
    expect(find.text('설정에서 켜기'), findsNothing, reason: '아직 거부한 적이 없다');
    expect(opened(), 0, reason: 'OS 대화상자는 추적 화면이 부른다 — 시트 확인 전에는 열지 않는다');

    await t.tap(find.text('허용하기'));
    await t.pumpAndSettle();

    expect(opened(), 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LocationPriming.askedKey), isTrue, reason: '다음에 또 거부 상태면 설정 길을 보여 준다');
  });

  testWidgets('"나중에" 면 열지 않는다', (t) async {
    LocationPriming.checkPermission = () async => LocationPermission.denied;
    final opened = await _pump(t);

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();
    await t.tap(find.text('나중에'));
    await t.pumpAndSettle();

    expect(opened(), 0);
    expect(find.text('허용하기'), findsNothing);
  });

  testWidgets('이미 허용됐으면 시트 없이 바로 연다', (t) async {
    LocationPriming.checkPermission = () async => LocationPermission.whileInUse;
    final opened = await _pump(t);

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();

    expect(find.text('허용하기'), findsNothing);
    expect(opened(), 1);
  });

  testWidgets('한 번 거부한 뒤 다시 시작하면 "설정에서 켜기" 가 함께 보인다', (t) async {
    SharedPreferences.setMockInitialValues({LocationPriming.askedKey: true});
    LocationPriming.checkPermission = () async => LocationPermission.denied;
    var settings = 0;
    LocationPriming.openSettings = () async {
      settings++;
      return true;
    };
    final opened = await _pump(t);

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();

    expect(find.text('허용하기'), findsOneWidget, reason: '앱이 다시 물을 수는 있다');
    expect(find.text('설정에서 켜기'), findsOneWidget);

    await t.tap(find.text('설정에서 켜기'));
    await t.pumpAndSettle();

    expect(settings, 1);
    expect(opened(), 0, reason: '설정으로 보냈으면 추적 화면은 열지 않는다');
  });

  testWidgets('OS 가 다시 묻지 못하게 했으면(deniedForever) 설정에서 켜기가 주 버튼이다', (t) async {
    LocationPriming.checkPermission = () async => LocationPermission.deniedForever;
    var settings = 0;
    LocationPriming.openSettings = () async {
      settings++;
      return true;
    };
    final opened = await _pump(t);

    await t.tap(find.text('산책 시작'));
    await t.pumpAndSettle();

    expect(find.text('위치 권한이 꺼져 있어요'), findsOneWidget);
    expect(find.text('허용하기'), findsNothing, reason: '앱에서는 다시 여쭤볼 수 없다');
    expect(find.text('설정에서 켜기'), findsOneWidget);

    await t.tap(find.text('설정에서 켜기'));
    await t.pumpAndSettle();
    expect(settings, 1);
    expect(opened(), 0);
  });
}

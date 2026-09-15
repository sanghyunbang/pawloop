// 설명 없이 권한을 묻지 않는다 — 이슈 #517.
//
// 예전에는 홈에 들어오는 순간 카드가 `LocationService.locate()` 를 불렀고, 그 안에서 OS
// 권한 대화상자가 떴다. 사용자는 **왜 묻는지 모르는 채** 대화상자를 만나고, 거기서 한 번
// 거부하면 안드로이드는 두 번째 거부에서 영구 거부로 굳힌다 — 그 뒤로는 앱이 다시 물을
// 수도 없다.
//
// 지금은 묻지 않고, 대신 **왜 카드가 없는지 말하고 길을 준다.** 누르면 설명 시트가 먼저다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_safety_card.dart';

WalkSafetyRepository _repo() => WalkSafetyRepository(
      client: MockClient((req) async => http.Response(
            jsonEncode({
              'tempC': 22.0,
              'humidity': 49,
              'rain1hMm': 0.0,
              'precipType': 0,
              'pm10': null,
              'pm25': null,
              'station': null,
              'observedAt': '2026-09-07T05:10:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          )),
      baseUrl: 'https://api.example.test',
      now: () => DateTime(2026, 9, 7, 14, 10),
    );

LocationFix _fix() => LocationFix.found(Position(
      latitude: 37.5445,
      longitude: 127.0410,
      timestamp: DateTime(2026, 9, 7, 14, 10),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));

final _ask = find.byKey(const Key('walk-safety-ask-location'));

Future<void> _pump(
  WidgetTester t, {
  required Future<LocationFix> Function() locate,
  Future<bool> Function(BuildContext context)? onAskLocation,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WalkSafetyCard(
        repository: _repo(),
        locate: locate,
        now: () => DateTime(2026, 9, 7, 14, 10),
        onAskLocation: onAskLocation,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.clear();
    kMyDog.value = null;
    LocationService.consented.value = false;
  });

  tearDown(() => LocationService.consented.value = false);

  testWidgets('권한이 없으면 "위치를 켜면…" 한 줄이 뜬다 — 카드가 말없이 사라지지 않는다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.denied),
        onAskLocation: (_) async => false);

    expect(_ask, findsOneWidget);
    expect(find.text('위치를 켜면 오늘 산책하기 좋은지 알려드려요'), findsOneWidget);
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('동의 전이면 안내를 안 띄운다 — 그건 동의 화면이 받는 자리다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.notConsented),
        onAskLocation: (_) async => true);

    expect(_ask, findsNothing);
  });

  testWidgets('사용자가 스스로 중단한 것에는 잔소리하지 않는다', (t) async {
    await _pump(t,
        locate: () async => const LocationFix.denied(LocationDenial.pausedByUser),
        onAskLocation: (_) async => true);

    expect(_ask, findsNothing);
  });

  testWidgets('"허용" 을 누르면 설명을 먼저 띄우는 손이 불리고, 허용되면 카드가 나온다', (t) async {
    var asked = 0;
    var allowed = false;
    await _pump(t,
        locate: () async => allowed ? _fix() : const LocationFix.denied(LocationDenial.denied),
        onAskLocation: (_) async {
          asked++;
          allowed = true;
          return true;
        });
    expect(_ask, findsOneWidget);

    await t.tap(find.text('허용'));
    await t.pumpAndSettle();

    expect(asked, 1, reason: 'OS 에 바로 묻지 않는다 — 설명하는 자리를 지난다');
    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
    expect(_ask, findsNothing);
  });

  testWidgets('안내 손을 안 꽂으면 줄도 안 그린다 — 누를 곳 없는 안내는 안 띄운다', (t) async {
    await _pump(t, locate: () async => const LocationFix.denied(LocationDenial.denied));

    expect(_ask, findsNothing);
  });
}

// 홈 안전 지수 카드 — 없으면 없고, 있으면 한 줄과 근거, 누르면 7초 룰 (#336).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_safety_card.dart';

WalkSafetyRepository _repo({double temp = 22, int status = 200}) => WalkSafetyRepository(
      client: MockClient((req) async => http.Response(
            jsonEncode(status == 200
                ? {'tempC': temp, 'humidity': 49, 'rain1hMm': 0.0, 'precipType': 0, 'pm10': null, 'pm25': null, 'station': null, 'observedAt': '2026-09-07T05:10:00Z'}
                : {'error': {'code': 'UPSTREAM', 'message': '지금 기상 정보를 받지 못했습니다.'}}),
            status,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          )),
      baseUrl: 'https://api.example.test',
      now: () => DateTime(2026, 9, 7, 14, 10),
    );

Future<void> _pump(WidgetTester t, WalkSafetyRepository repo, {bool located = true}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WalkSafetyCard(
        repository: repo,
        locate: () async => located ? (lat: 37.5445, lng: 127.0410) : null,
        now: () => DateTime(2026, 9, 7, 14, 10),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WalkSafetyStore.resetForTest();
    kMyDog.value = null;
    LocationService.consented.value = false;
  });

  tearDown(() => LocationService.consented.value = false);

  testWidgets('서버가 503 이면 카드가 없다 — 가짜를 놓지 않는다', (t) async {
    await _pump(t, _repo(status: 503));
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('위치가 없으면(게스트) 카드가 없다', (t) async {
    await _pump(t, _repo(), located: false);
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('값이 오면 한 줄과 근거 — "지금 나가기 좋아요 · 22°C · 미세먼지 정보 없음"', (t) async {
    await _pump(t, _repo());

    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
    expect(find.text('22°C · 미세먼지 정보 없음'), findsOneWidget);
    expect(find.textContaining('24°C'), findsNothing, reason: '하드코딩이 아니다');
  });

  testWidgets('누르면 7초 룰과 시간대, 그리고 "참고" 라는 말이 뜬다', (t) async {
    await _pump(t, _repo(temp: 31));

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
    await t.tap(find.text('지금은 피하고 저녁 7시 뒤에'));
    await t.pumpAndSettle();

    expect(find.textContaining('7초'), findsOneWidget);
    expect(find.textContaining('오전 10시 전'), findsOneWidget);
    expect(find.textContaining('참고 기준'), findsOneWidget);
    expect(find.text('습도 49%'), findsOneWidget);
  });

  testWidgets('아이가 바뀌면 같은 값으로 다시 판정한다 — 퍼그면 27°C 낮에 피하세요', (t) async {
    await _pump(t, _repo(temp: 27));
    expect(find.text('짧게 다녀오세요 · 바닥 7초 룰 확인'), findsOneWidget);

    kMyDog.value = const DogProfile(serverId: 2, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 30);
    await t.pumpAndSettle();

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
  });

  testWidgets('첫 시도에 위치가 없어도 동의가 켜지면 다시 부른다 — 카드가 뒤늦게 나온다', (t) async {
    var located = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkSafetyCard(
          repository: _repo(),
          locate: () async => located ? (lat: 37.5445, lng: 127.0410) : null,
          now: () => DateTime(2026, 9, 7, 14, 10),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('°C'), findsNothing);

    // 라우터가 저장소를 읽고 뒤늦게 써 준다 — 그 전에 만들어진 카드가 그대로 비어 있으면
    // 앱을 껐다 켜기 전에는 안전 지수를 볼 수 없다.
    located = true;
    LocationService.consented.value = true;
    await t.pumpAndSettle();

    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });

  testWidgets('앱으로 돌아오면 다시 부른다 — 실내에서 못 잡고 나갔다 온 자리', (t) async {
    var located = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkSafetyCard(
          repository: _repo(),
          locate: () async => located ? (lat: 37.5445, lng: 127.0410) : null,
          now: () => DateTime(2026, 9, 7, 14, 10),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('°C'), findsNothing);

    located = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.text('지금 나가기 좋아요'), findsOneWidget);
  });
}

// 홈 안전 지수 카드 — 없으면 없고, 있으면 한 줄과 근거, 누르면 7초 룰 (#336).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_safety_card.dart';

WalkSafetyRepository _repo({String temp = '22', String key = 'KEY'}) => WalkSafetyRepository(
      client: MockClient((req) async {
        if (req.url.path.contains('getUltraSrtNcst')) {
          return http.Response(
            jsonEncode({
              'response': {
                'header': {'resultCode': '00'},
                'body': {
                  'items': {
                    'item': [
                      {'category': 'T1H', 'obsrValue': temp},
                      {'category': 'REH', 'obsrValue': '49'},
                      {'category': 'PTY', 'obsrValue': '0'},
                    ]
                  }
                }
              }
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"OpenAPI_ServiceResponse":{}}', 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }),
      serviceKey: key,
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
    WalkSafetyRepository.resetForTest();
    WalkSafetyStore.resetForTest();
    kMyDog.value = null;
  });

  testWidgets('키가 없으면 카드가 없다 — 가짜를 놓지 않는다', (t) async {
    await _pump(t, _repo(key: ''));
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
    await _pump(t, _repo(temp: '31'));

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
    await t.tap(find.text('지금은 피하고 저녁 7시 뒤에'));
    await t.pumpAndSettle();

    expect(find.textContaining('7초'), findsOneWidget);
    expect(find.textContaining('오전 10시 전'), findsOneWidget);
    expect(find.textContaining('참고 기준'), findsOneWidget);
    expect(find.text('습도 49%'), findsOneWidget);
  });

  testWidgets('아이가 바뀌면 같은 값으로 다시 판정한다 — 퍼그면 27°C 낮에 피하세요', (t) async {
    await _pump(t, _repo(temp: '27'));
    expect(find.text('짧게 다녀오세요 · 바닥 7초 룰 확인'), findsOneWidget);

    kMyDog.value = const DogProfile(serverId: 2, name: 'Pug', breed: '퍼그', size: DogSize.small, ageMonths: 30);
    await t.pumpAndSettle();

    expect(find.text('지금은 피하고 저녁 7시 뒤에'), findsOneWidget);
  });
}

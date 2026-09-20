// 장소 시트의 추천 코스 고르기 — 이슈 #725.
//
// 진짜 `PlaceLoopRepository` 에 `MockClient`. 여기서 재는 것.
//   - 열면 2km 를 묻고 **실제** 길이·시간을 적는다(부탁한 2km 가 아니라 2.1km)
//   - 칩을 누르면 그 길이로 다시 묻고, 받은 선을 onLoop 로 건넨다
//   - 못 받으면(available:false · 5xx) 그렇다고 말하고 onLoop 는 null
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/v2/data/place_loop_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/place_loop_picker.dart';

const _base = 'https://api.example.test';

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> loopJson({int targetM = 2000, int distanceM = 2130, int durationS = 1704}) => {
      'contentId': '2745594',
      'targetM': targetM,
      'available': true,
      'reason': null,
      'distanceM': distanceM,
      'durationS': durationS,
      'pointCount': 3,
      'points': [
        [127.037552, 37.544284],
        [127.0405, 37.5462],
        [127.037552, 37.544284],
      ],
    };

const unavailableJson = {
  'contentId': '2745594',
  'targetM': 2000,
  'available': false,
  'reason': 'budget',
  'distanceM': null,
  'durationS': null,
  'pointCount': 0,
  'points': [],
};

class LoopFixture {
  final PlaceLoopRepository repo;
  final List<http.Request> requests;
  LoopFixture(this.repo, this.requests);
}

LoopFixture fixture(http.Response Function(http.Request request) answer) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return answer(request);
  });
  return LoopFixture(PlaceLoopRepository(baseUrl: _base, client: client), requests);
}

Future<List<PlaceLoop?>> pump(WidgetTester tester, LoopFixture f) async {
  final got = <PlaceLoop?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      // 같은 자리에 같은 종류를 다시 띄우면 State 가 재사용돼 initState 가 안 돈다 — 매번 새 키.
      body: PlaceLoopPicker(key: UniqueKey(), contentId: '2745594', repository: f.repo, onLoop: got.add),
    ),
  ));
  await tester.pumpAndSettle();
  return got;
}

void main() {
  testWidgets('열면 2km 를 묻고 실제 길이·시간을 적는다 — 부탁한 2km 가 아니라 2.1km', (tester) async {
    final f = fixture((_) => _json(loopJson()));
    final got = await pump(tester, f);

    final req = f.requests.single;
    expect(req.url.path, '/api/places/2745594/loop');
    expect(req.url.queryParameters['lengthM'], '2000');
    expect(find.text('실제 2.1km · 약 28분 — "이 코스 걷기" 를 누르면 지도에 선으로 깔려요'), findsOneWidget,
        reason: '카드는 부탁한 길이가 아니라 나온 길이를 적는다');
    expect(got.last, isNotNull);
    expect(got.last!.lngLat, hasLength(3));
    expect(got.last!.lngLat.first, [127.037552, 37.544284]);
  });

  testWidgets('1km 칩을 누르면 1km 로 다시 묻고, 받은 선을 다시 건넨다', (tester) async {
    final f = fixture((request) => request.url.queryParameters['lengthM'] == '1000'
        ? _json(loopJson(targetM: 1000, distanceM: 1200, durationS: 960))
        : _json(loopJson()));
    final got = await pump(tester, f);

    await tester.tap(find.byKey(const Key('loop-len-1000')));
    await tester.pumpAndSettle();

    expect(f.requests.last.url.queryParameters['lengthM'], '1000');
    expect(find.textContaining('실제 1.2km · 약 16분'), findsOneWidget);
    expect(got.where((l) => l == null).length, greaterThanOrEqualTo(2),
        reason: '다시 묻는 동안 null 을 한 번 건넨다 — 옛 선을 들고 나가면 안 된다');
    expect(got.last!.distanceM, 1200);
  });

  testWidgets('못 받으면 그렇다고 말한다 — available:false 도, 5xx 도', (tester) async {
    final f = fixture((_) => _json(unavailableJson));
    final got = await pump(tester, f);
    expect(find.byKey(const Key('loop-unavailable')), findsOneWidget);
    expect(find.text('지금은 추천 코스를 못 받아요'), findsOneWidget);
    expect(got.last, isNull);

    final g = fixture((_) => _json({'error': {}}, status: 500));
    final got2 = await pump(tester, g);
    expect(find.byKey(const Key('loop-unavailable')), findsOneWidget);
    expect(got2.last, isNull);
  });

  test('PlaceLoop 은 선이 두 점 미만이거나 available 이 아니면 null', () {
    expect(PlaceLoop.tryParse(Map<String, dynamic>.from(unavailableJson)), isNull);
    final onePoint = Map<String, dynamic>.from(loopJson())..['points'] = [[127.0, 37.5]];
    expect(PlaceLoop.tryParse(onePoint), isNull);
    final ok = PlaceLoop.tryParse(Map<String, dynamic>.from(loopJson()))!;
    expect(ok.distanceLabel, '2.1km');
    expect(ok.timeLabel, '약 28분');
    // 계약이 "줄 수 있다" 고 말하는 값은 available 하나다 — 선이 남아 있어도 거짓이면 안 믿는다.
    final staleButUnavailable = Map<String, dynamic>.from(loopJson())..['available'] = false;
    expect(PlaceLoop.tryParse(staleButUnavailable), isNull,
        reason: 'available 이 거짓인데 선을 그리면 "지금은 없음" 을 "있음" 으로 바꾸는 것이다');
  });
}

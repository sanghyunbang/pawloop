// `2회` 가 되면 **누가 했는지가 사라지던** 자리 — 이슈 #570.
//
// ## 무엇이 있었나
//
// 아빠와 엄마가 밥을 한 번씩 준 날, 칸이 이렇게만 남았다.
//
// ```
//    🍽
//    밥
//   2회
//  10:39
// ```
//
// 둘이 한 번씩인지 한 사람이 두 번인지 알 수 없고, 누가 했는지도 알 수 없다. 이 앱의
// 목적은 업무 분담과 누락 방지인데(#76), 분담을 보이게 하려던 칸이 **분담을 가리는 칸**이
// 됐다. #561 이 "밥은 한 번이 아니라 횟수가 있다" 를 고치면서 횟수를 얻고 사람을 잃었다.
//
// ## 여기서 지키는 것
//
//  1. 두 번 이상이면 셋째 줄이 **시각 대신 사람**이다.
//  2. "오늘 한 일" 이 시간까지 펼친다 — **누락은 칸이, 분담은 이 줄이** 말한다.
//  3. 홈은 **최근 셋**만 본다. 이른 것부터 자르면 방금 누른 것이 안 보인다.
//  4. 우리 가족 화면은 전부 편다 — 거기가 "더 보기" 의 목적지다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'a';
  @override
  Future<String?> readRefreshToken() async => 'r';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

/// 계약대로 **이른 것부터** 준다.
Map<String, Object?> _log(
    {required int id,
    required String type,
    required int userId,
    required String name,
    required String at}) => {
      'id': id,
      'dogId': 1,
      'groupId': 3,
      'type': type,
      'doneBy': {'userId': userId, 'nickname': name},
      'occurredAt': '2026-09-16T$at',
      'memo': null,
    };

FamilyRepository _repoWith(List<Map<String, Object?>> logs) => FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          if (request.url.path == '/api/groups/me') {
            return http.Response(
                jsonEncode({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []}), 200,
                headers: const {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response(jsonEncode(logs), 200,
              headers: const {'content-type': 'application/json; charset=utf-8'});
        }),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

Future<void> _pump(WidgetTester t, FamilyRepository repo,
    {VoidCallback? onOpenFamily}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TodayCareCard(
          repository: repo,
          myUserId: 11,
          onOpenFamily: onOpenFamily,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

String _line2(WidgetTester t, String wire) =>
    t.widget<Text>(find.byKey(Key('care-line2-$wire'))).data!;

/// 로그 줄은 **열쇠로** 찾는다. 칸의 셋째 줄과 글자가 같아서(`10:39`) `find.text` 로는
/// 둘이 안 갈린다 — 실제로 처음엔 "두 개 찾음" 으로 빨갰다.
Finder _logRow(int id) => find.byKey(Key('care-log-$id'));

void main() {
  setUp(() => replacePets(const []));

  testWidgets('둘이 한 번씩 하면 칸이 두 사람을 말한다 — "2회 · 10:39" 로는 구별이 안 된다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: '엄마', at: '08:10:00'),
        _log(id: 2, type: 'meal', userId: 11, name: '아빠', at: '12:10:00'),
      ]),
      onOpenFamily: () {},
    );

    expect(find.byKey(const Key('care-line1-meal')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('care-line1-meal'))).data, '2회');
    expect(_line2(t, 'meal'), '아빠·엄마',
        reason: '시각 하나를 적으면 나머지가 숨는다. 분담이 보이려면 사람이 보여야 한다');
  });

  testWidgets('한 사람이 두 번 하면 그 한 사람만 말한다 — 둘이 한 번씩인 날과 달라야 한다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 11, name: '아빠', at: '08:10:00'),
        _log(id: 2, type: 'meal', userId: 11, name: '아빠', at: '12:10:00'),
      ]),
      onOpenFamily: () {},
    );

    expect(t.widget<Text>(find.byKey(const Key('care-line1-meal'))).data, '2회');
    expect(_line2(t, 'meal'), '아빠');
  });

  testWidgets('한 번이면 전과 같이 시각이다 — 고치면서 평소 화면을 바꾸지 않는다', (t) async {
    await _pump(
      t,
      _repoWith([_log(id: 1, type: 'water', userId: 22, name: '엄마', at: '10:39:00')]),
      onOpenFamily: () {},
    );

    expect(t.widget<Text>(find.byKey(const Key('care-line1-water'))).data, '엄마');
    expect(_line2(t, 'water'), '10:39');
  });

  testWidgets('이름이 길면 "외 N" 으로 접는다 — 좁은 칸에서 두 이름은 안 들어간다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: '할머니', at: '08:10:00'),
        _log(id: 2, type: 'meal', userId: 11, name: '아버지', at: '12:10:00'),
      ]),
      onOpenFamily: () {},
    );

    expect(_line2(t, 'meal'), '아버지 외 1');
  });

  testWidgets('"오늘 한 일" 이 시간까지 펼친다 — 누락은 칸이, 분담은 이 줄이 말한다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: '엄마', at: '08:10:00'),
        _log(id: 2, type: 'water', userId: 11, name: '아빠', at: '10:39:00'),
      ]),
      onOpenFamily: () {},
    );

    expect(find.byKey(const Key('care-log-title')), findsOneWidget);
    expect(_logRow(1), findsOneWidget);
    expect(_logRow(2), findsOneWidget);
    expect(find.descendant(of: _logRow(1), matching: find.text('08:10')), findsOneWidget);
    expect(find.descendant(of: _logRow(1), matching: find.text('엄마')), findsOneWidget);
    expect(find.descendant(of: _logRow(1), matching: find.text('밥')), findsOneWidget);
    expect(find.descendant(of: _logRow(2), matching: find.text('아빠')), findsOneWidget);
  });

  testWidgets('홈은 최근 셋만 본다 — 이른 것부터 자르면 방금 누른 것이 안 보인다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: '엄마', at: '07:00:00'),
        _log(id: 2, type: 'water', userId: 22, name: '엄마', at: '08:00:00'),
        _log(id: 3, type: 'walk', userId: 11, name: '아빠', at: '09:00:00'),
        _log(id: 4, type: 'med', userId: 11, name: '아빠', at: '10:00:00'),
        _log(id: 5, type: 'vet', userId: 11, name: '아빠', at: '11:00:00'),
      ]),
      onOpenFamily: () {},
    );

    expect(_logRow(5), findsOneWidget, reason: '가장 최근이 빠지면 방금 누른 것이 안 보인다');
    expect(_logRow(4), findsOneWidget);
    expect(_logRow(3), findsOneWidget);
    expect(_logRow(2), findsNothing);
    expect(_logRow(1), findsNothing);
    expect(find.byKey(const Key('care-log-rest')), findsOneWidget);
    expect(find.text('그 전에 2개'), findsOneWidget);
  });

  testWidgets('우리 가족 화면은 전부 편다 — 거기가 "더 보기" 의 목적지다 (#570)', (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: '엄마', at: '07:00:00'),
        _log(id: 2, type: 'water', userId: 22, name: '엄마', at: '08:00:00'),
        _log(id: 3, type: 'walk', userId: 11, name: '아빠', at: '09:00:00'),
        _log(id: 4, type: 'med', userId: 11, name: '아빠', at: '10:00:00'),
        _log(id: 5, type: 'vet', userId: 11, name: '아빠', at: '11:00:00'),
      ]),
      // onOpenFamily 가 null 이면 이미 그 화면 안이다.
    );

    expect(_logRow(1), findsOneWidget);
    expect(_logRow(5), findsOneWidget);
    expect(find.byKey(const Key('care-log-rest')), findsNothing);
  });

  testWidgets('긴 이름도 줄을 안 밀어낸다 — 종류가 들쭉날쭉 앉으면 안 읽힌다 (#570)',
      (t) async {
    await _pump(
      t,
      _repoWith([
        _log(id: 1, type: 'meal', userId: 22, name: 'CrewOwner', at: '08:10:00'),
        _log(id: 2, type: 'water', userId: 11, name: '아빠', at: '10:39:00'),
      ]),
      onOpenFamily: () {},
    );

    // 넘침이 나면 여기서 예외가 잡힌다.
    expect(t.takeException(), isNull);
    // 이름이 길든 짧든 종류는 **같은 자리**에서 시작한다.
    final a = t.getTopLeft(find.descendant(of: _logRow(1), matching: find.text('밥')));
    final b = t.getTopLeft(find.descendant(of: _logRow(2), matching: find.text('물')));
    expect(a.dx, b.dx, reason: '훑을 때 눈이 따라가는 세로줄이 "무엇" 이다');
  });

  testWidgets('아무 기록도 없으면 이 줄이 자리를 안 차지한다', (t) async {
    await _pump(t, _repoWith(const []), onOpenFamily: () {});

    expect(find.byKey(const Key('care-log-title')), findsNothing);
  });
}

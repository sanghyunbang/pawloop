// 가족이 오늘 이미 걸었다는 것을 홈이 말한다 — 이슈 #343.
//
// ## 여기서 재는 것
//
//  1. **남이 걸었을 때만 뜬다.** 내가 걸은 것은 내가 안다 — 방금 한 일을 다시 읽어 주는
//     줄은 자리만 차지한다.
//  2. **막지 않는다.** 하루 두 번 걷는 집도 있다. 몰라서 두 번 나가는 것과 알고 두 번
//     나가는 것은 다르다 — 이 줄은 알게 할 뿐이다.
//  3. **거리는 케어 로그 메모에서 온다.** 없으면 거리 없이 적는다(옛 기록·손으로 누른 칸).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';
  @override
  Future<String?> readRefreshToken() async => 'refresh-token';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _walkLog({
  required int userId,
  required String who,
  required String at,
  String? memo,
}) =>
    {
      'id': 41,
      'dogId': null,
      'groupId': 3,
      'type': 'walk',
      'doneBy': {'userId': userId, 'nickname': who},
      'occurredAt': at,
      'memo': memo,
    };

FamilyRepository _repo(List<Map<String, Object?>> logs) => FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async {
          if (request.url.path == '/api/groups/me') {
            return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
          }
          return _json(logs);
        }),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

Future<void> _pump(WidgetTester t, List<Map<String, Object?>> logs, {int? me}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: TodayCareCard(repository: _repo(logs), myUserId: me)),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('아빠가 아침에 걸었으면 한 줄이 뜬다', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '아빠', at: '2026-09-08T08:10:00', memo: '1.2km')],
      me: 22,
    );

    expect(find.text('아빠가 아침에 1.2km 걸었어요'), findsOneWidget);
  });

  testWidgets('내가 걸은 것은 안 적는다 — 방금 한 일을 다시 읽어 줄 이유가 없다', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 22, who: '나', at: '2026-09-08T08:10:00', memo: '1.2km')],
      me: 22,
    );

    expect(find.textContaining('걸었어요'), findsNothing);
  });

  testWidgets('거리가 없으면 거리 없이 적는다 — 손으로 누른 산책 칸에는 메모가 없다', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '엄마', at: '2026-09-08T19:30:00')],
      me: 22,
    );

    expect(find.text('엄마가 저녁에 걸었어요'), findsOneWidget);
  });

  testWidgets('아무도 안 걸었으면 줄 자체가 없다', (t) async {
    await _pump(t, const [], me: 22);

    expect(find.textContaining('걸었어요'), findsNothing);
  });

  testWidgets('막지 않는다 — 산책 칸은 그대로 누를 수 있다', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '아빠', at: '2026-09-08T08:10:00', memo: '1.2km')],
      me: 22,
    );

    // 칸이 사라지거나 잠기지 않는다. "알게 한다" 이지 "막는다" 가 아니다.
    expect(find.text('산책'), findsOneWidget);
  });

  testWidgets('산책 칸에 거리가 함께 보인다 — 엄마 · 08:10 · 1.2km', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '엄마', at: '2026-09-08T08:10:00', memo: '1.2km')],
      me: 22,
    );

    expect(find.text('엄마'), findsOneWidget);
    expect(find.text('08:10'), findsOneWidget);
    expect(find.text('1.2km'), findsOneWidget);
  });
}

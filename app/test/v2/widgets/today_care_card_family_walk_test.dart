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

/// [id] 는 행마다 달라야 한다 — "오늘 한 일" 줄이 id 로 열쇠를 만든다(#570).
int _walkLogSeq = 40;

Map<String, Object?> _walkLog({
  required int userId,
  required String who,
  required String at,
  String? memo,
}) =>
    {
      'id': ++_walkLogSeq,
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
    // (#570 뒤로는 "오늘 한 일" 줄에도 '산책' 이 있어서 **칸을 열쇠로** 찾는다.)
    expect(find.byKey(const Key('care-cell-walk')), findsOneWidget);
  });

  testWidgets('산책 칸은 거리 · 시각이고, 이름은 바로 위 한 줄이 말한다 (#561)', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '엄마', at: '2026-09-08T08:10:00', memo: '1.2km')],
      me: 22,
    );

    expect(t.widget<Text>(find.byKey(const Key('care-line1-walk'))).data, '1.2km');
    expect(t.widget<Text>(find.byKey(const Key('care-line2-walk'))).data, '08:10');
    expect(find.text('엄마가 아침에 1.2km 걸었어요'), findsOneWidget,
        reason: '칸에서 이름이 빠져도 화면에서 사라지지 않는다 — 이 줄이 이름과 거리를 둘 다 말한다');
  });

  testWidgets('거리가 없으면 칸은 이름을 말한다 — 손으로 누른 산책이다', (t) async {
    await _pump(
      t,
      [_walkLog(userId: 11, who: '엄마', at: '2026-09-08T08:10:00')],
      me: 22,
    );

    expect(t.widget<Text>(find.byKey(const Key('care-line1-walk'))).data, '엄마');
  });

  testWidgets('두 번 걸었으면 거리보다 횟수가 먼저다 — 두 번째를 막으려고 보는 자리다 (#561)', (t) async {
    await _pump(
      t,
      [
        _walkLog(userId: 11, who: '엄마', at: '2026-09-08T08:10:00', memo: '1.2km'),
        _walkLog(userId: 11, who: '아빠', at: '2026-09-08T19:30:00', memo: '0.8km'),
      ],
      me: 22,
    );

    expect(t.widget<Text>(find.byKey(const Key('care-line1-walk'))).data, '2회');
    // **#570 이 바꿨다** — 두 번 이상이면 사람이다. 여기서는 둘 다 같은 `userId` 라
    // 한 사람으로 접힌다(닉네임만 다른 같은 계정).
    expect(t.widget<Text>(find.byKey(const Key('care-line2-walk'))).data, '아빠',
        reason: '분담이 보이려면 시각이 아니라 사람이 보여야 한다');
  });
}

// 오늘의 케어 칸 라벨 — 이름과 시각이 따로 있어 시각이 잘리지 않는다 (#326).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

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

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('긴 닉네임이어도 시각 "15:40" 은 온전히 보인다', (tester) async {
    AuthState.signInForTest(const AuthUser(id: 11, nickname: 'walker'));
    final client = AuthedClient(
      inner: MockClient((request) async {
        if (request.url.path == '/api/groups/me') {
          return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
        }
        return _json([
          {
            'id': 1, 'dogId': null, 'groupId': 3, 'type': 'water',
            'doneBy': {'userId': 11, 'nickname': 'walker-with-a-very-long-name'},
            'occurredAt': '2026-09-07T15:40:00', 'memo': null,
          },
        ]);
      }),
      baseUrl: 'https://api.example.test',
      store: _Tokens(),
    );
    final repo = FamilyRepository(baseUrl: 'https://api.example.test', client: client);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayCareCard(repository: repo))));
    await tester.pumpAndSettle();

    // **칸 안에서 찾는다**(#570). 아래 "오늘 한 일" 줄에도 같은 시각·이름이 있어서
    // `find.text` 로는 둘이 안 갈린다.
    expect(tester.widget<Text>(find.byKey(const Key('care-line2-water'))).data, '15:40',
        reason: '시각은 제 줄에 온전히');
    expect(tester.widget<Text>(find.byKey(const Key('care-line1-water'))).data,
        'walker-with-a-very-long-name',
        reason: '이름은 제 줄에서 줄임표');
    expect(find.textContaining(' · 15'), findsNothing, reason: '한 줄로 붙이지 않는다');
  });
}

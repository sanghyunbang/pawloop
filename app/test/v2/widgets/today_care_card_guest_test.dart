// "오늘의 케어" 카드 — 게스트 (#324).
//
// 로그인한 적 없는 사람에게 카드가 401 을 받아 "다시 로그인해 주세요" 라고 말했다.
// 이제 서버를 **부르지 않고** "로그인하면" 을 말한다. 요청이 한 건이라도 나가면 빨강.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('게스트에게는 "로그인하면" 이고, 서버 요청은 0 이다', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    final requests = <http.Request>[];
    final repo = FamilyRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((request) async {
          requests.add(request);
          return http.Response('{"error":{}}', 401);
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayCareCard(repository: repo))));
    await tester.pumpAndSettle();

    expect(find.text('로그인하면 가족과 오늘의 케어를 나눠요'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.textContaining('다시 로그인'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    expect(requests, isEmpty, reason: '게스트는 서버를 부르지 않는다');

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

// 채팅 탭 — 게스트 (#324).
//
// "로그인이 필요해요" 카드에 버튼이 없었고, 그 아래 "우리 가족 관리"·"초대코드로 참여" 는
// 눌러도 안 되는 항목이었다. 이제 카드에 로그인 버튼이 있고 아래 둘은 없다. 서버 요청 0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';

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

  testWidgets('게스트: 로그인 버튼이 있고, 가족 관리·초대 참여는 없고, 요청은 0', (tester) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    var calls = 0;
    final repo = ChatRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('{"error":{}}', 401);
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: ChatListScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.textContaining('우리 가족 관리'), findsNothing);
    expect(find.text('초대코드로 참여'), findsNothing);
    expect(calls, 0);

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

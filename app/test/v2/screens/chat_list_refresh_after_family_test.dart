// 가족을 만들고 돌아오면 방 목록을 다시 받는가.
//
// 2026-09-17 실기기: 채팅 탭에서 "우리 가족 관리" 로 들어가 가족을 만들고 나왔는데
// **"아직 참여한 방이 없어요" 가 그대로**였다. 앱을 껐다 켜야 보였다.
//
// 탭을 오가면 이 화면의 State 가 새로 만들어져 `initState` 가 다시 받는다. 그래서
// **탭 안에서 화면을 얹었다 내리는 이 길만** 구멍이었다 — 바로 아래 "초대코드로 참여"
// 는 처음부터 `await` 뒤에 다시 받고 있었다. 한 화면 안에서 두 버튼이 다르게 굴었다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';

const _base = 'https://api.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT';
  @override
  Future<String?> readRefreshToken() async => 'RT';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _oneRoom = '[{"id":1,"title":"우리 가족","tag":"가족","lastSeq":0,"lastReadSeq":0,'
    '"unread":0,"memberCount":1,"myRole":"OWNER","muted":false}]';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: '보리아빠'));
  });

  testWidgets('"우리 가족 관리" 에 들어갔다 나오면 방 목록을 다시 받는다', (tester) async {
    var roomCalls = 0;

    final repo = ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((req) async {
          const json = {'content-type': 'application/json; charset=utf-8'};
          if (req.method == 'GET' && req.url.path == '/api/chat/rooms') {
            roomCalls++;
            // 첫 번째는 방이 없고, 두 번째부터 가족방이 있다 — 그 사이에 만들었다는 뜻이다.
            return http.Response(roomCalls == 1 ? '[]' : _oneRoom, 200, headers: json);
          }
          // 가족 화면이 저를 위해 부르는 것들. 여기서 재는 것이 아니라 막지만 않으면 된다.
          return http.Response('{}', 404, headers: json);
        }),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: ChatListScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(roomCalls, 1);
    expect(find.textContaining('아직 참여한 방이 없어요'), findsOneWidget);

    await tester.tap(find.textContaining('우리 가족 관리'));
    await tester.pumpAndSettle();

    // 가족 화면에서 가족을 만들었다고 치고 돌아온다. 그 화면이 무엇을 그리는지는
    // 여기서 재지 않는다 — 재는 것은 **돌아온 뒤 목록을 다시 받는가** 하나다.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(roomCalls, 2,
        reason: '돌아왔는데 다시 안 받으면 방금 만든 가족이 안 보인다 — 앱을 껐다 켜야 한다');
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.textContaining('아직 참여한 방이 없어요'), findsNothing);
  });
}

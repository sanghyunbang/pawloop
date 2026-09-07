import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/chat_terms_gate.dart';
import 'package:heat_trip_flutter/v2/screens/family_chat_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 채팅 첫 진입의 약관 동의 — 이슈 #82 완료 조건 6 (Google Play UGC 정책).
///
/// ## 여기서 재는 것
///
/// **동의를 받기 전에 대화를 받지 않는다.** 받아 두면 창을 닫는 순간 남의 말이 화면에
/// 그려진다 — 동의 화면이 있으나 마나가 된다.
///
/// 그리고 **한 번 동의하면 다시 안 묻는다.** 매번 물으면 사용자가 읽지 않고 누르게 되고,
/// 그건 동의를 받는 것이 아니라 절차를 밟는 것이다.
const String _base = 'https://api.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';

  @override
  Future<String?> readRefreshToken() async => 'RT-1';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

/// 서버를 부른 횟수를 센다.
class _CountingRepo {
  int calls = 0;

  ChatRepository build() => ChatRepository(
        baseUrl: _base,
        client: AuthedClient(
          inner: MockClient((req) async {
            calls++;
            return http.Response(
              '{"items":[{"id":1,"roomSeq":1,"senderUserId":9,'
              '"senderName":"엄마","body":"보리 저녁밥 줬어요"}],'
              '"lastSeq":1,"hasMore":false}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          baseUrl: _base,
          store: _FakeTokenStore(),
        ),
      );
}

Future<void> _pump(WidgetTester tester, ChatRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(roomId: 7, repository: repo),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.resetForTest();
    AuthState.signInForTest(const AuthUser(id: 42, nickname: '아빠'));
  });

  tearDown(AuthState.resetForTest);

  testWidgets('처음 들어가면 동의 창이 뜨고, 그 전에는 대화를 안 받는다', (tester) async {
    final counting = _CountingRepo();

    await _pump(tester, counting.build());

    expect(find.text('대화를 시작하기 전에'), findsOneWidget);
    expect(
      counting.calls,
      0,
      reason: '동의 전에 받아 두면 창을 닫는 순간 남의 말이 화면에 그려진다',
    );
    expect(find.text('보리 저녁밥 줬어요'), findsNothing);
  });

  testWidgets('동의 창이 탈퇴해도 메시지가 남는다는 것을 말한다', (tester) async {
    await _pump(tester, _CountingRepo().build());

    expect(
      find.textContaining('탈퇴해도 보낸 메시지는 대화방에 남아요'),
      findsOneWidget,
      reason: '접힌 두 줄 요약에서도 한 번은 말해야 나중에 "그런 말 없었다" 가 안 된다(#330)',
    );
    expect(find.textContaining('신고한 사실은 상대에게 알리지 않습니다'), findsNothing,
        reason: '네 줄은 "자세히" 뒤에 나온다');

    await tester.tap(find.text('자세히'));
    await tester.pumpAndSettle();

    expect(find.textContaining('탈퇴해도 이미 보낸 메시지는 대화방에 남고'), findsOneWidget);
    expect(find.textContaining('신고한 사실은 상대에게 알리지 않습니다'), findsOneWidget);
  });

  testWidgets('동의하면 대화가 뜬다', (tester) async {
    final counting = _CountingRepo();
    await _pump(tester, counting.build());

    await tester.tap(find.text('동의하고 시작'));
    await tester.pumpAndSettle();

    expect(find.text('보리 저녁밥 줬어요'), findsOneWidget);
    expect(counting.calls, greaterThan(0));
  });

  testWidgets('한 번 동의하면 다시 안 묻는다', (tester) async {
    await const ChatTermsGate().markAgreed(42);
    final counting = _CountingRepo();

    await _pump(tester, counting.build());

    expect(find.text('대화를 시작하기 전에'), findsNothing);
    expect(find.text('보리 저녁밥 줬어요'), findsOneWidget);
  });

  testWidgets('다른 계정에게는 다시 묻는다 — 한 기기를 가족이 나눠 쓴다', (tester) async {
    await const ChatTermsGate().markAgreed(42);
    AuthState.resetForTest();
    AuthState.signInForTest(const AuthUser(id: 99, nickname: '엄마'));

    await _pump(tester, _CountingRepo().build());

    expect(
      find.text('대화를 시작하기 전에'),
      findsOneWidget,
      reason: '앞사람의 동의가 뒷사람에게 적용되면 그 사람은 약관을 본 적이 없다',
    );
  });

  testWidgets('"나중에" 를 누르면 방을 열지 않는다 — 강제로 동의시키지 않는다', (tester) async {
    final counting = _CountingRepo();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FamilyChatScreen(roomId: 7, repository: counting.build()),
            )),
            child: const Text('방 열기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('방 열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();

    expect(find.text('방 열기'), findsOneWidget, reason: '되돌아와야 한다');
    expect(counting.calls, 0);
    expect(
      await const ChatTermsGate().hasAgreed(42),
      isFalse,
      reason: '거절을 동의로 남기면 다음 진입에서 창이 안 뜬다',
    );
  });
}

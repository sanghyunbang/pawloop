// 채팅방 **안에서** 주의 · 제재 안내를 다시 볼 수 있는가 (#682).
//
// ## 여기서 재는 것
//
// 입구에서 한 번 뜨고 마는 안내는 정작 돈이나 사진을 요구받는 순간에는 이미 사라진 뒤다.
// 원스토어 검증 가이드라인이 채팅에 요구하는 피해 예방 안내라, **이미 동의한 사람이** 방
// 안에서 다시 꺼내 읽을 수 있어야 한다. 그래서 동의를 마친 상태(창이 안 뜨는 상태)에서
// 머리말의 안내 버튼을 눌러 같은 문구가 나오는지 본다.
//
// 그리고 그 자리는 **동의를 다시 받는 자리가 아니다** — "동의하고 시작" 이 또 나오면
// 이미 동의한 사람에게 무엇에 동의하는 것인지 모호해진다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/chat_terms_gate.dart';
import 'package:heat_trip_flutter/v2/screens/family_chat_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/chat_terms_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ChatRepository _repo() => ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((req) async => http.Response(
              '{"items":[{"id":1,"roomSeq":1,"senderUserId":9,'
              '"senderName":"엄마","body":"보리 저녁밥 줬어요"}],'
              '"lastSeq":1,"hasMore":false}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
        baseUrl: _base,
        store: _FakeTokenStore(),
      ),
    );

/// 이미 동의를 마친 사람으로 방을 연다 — 첫 진입 창이 뜨지 않는 상태여야
/// "방 안에서 다시 볼 수 있는가" 를 재는 것이 된다.
Future<void> _openRoom(WidgetTester tester) async {
  await const ChatTermsGate().markAgreed(42);
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(roomId: 7, title: '우리 가족', repository: _repo()),
  ));
  await tester.pumpAndSettle();
}

final Finder _noticeButton = find.byKey(const ValueKey('chat_safety_notice_button'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.resetForTest();
    AuthState.signInForTest(const AuthUser(id: 42, nickname: '아빠'));
  });

  tearDown(AuthState.resetForTest);

  testWidgets('방 머리말에 안내 버튼이 있다 — 동의 창이 없는 상태에서도', (tester) async {
    await _openRoom(tester);

    expect(find.text('대화를 시작하기 전에'), findsNothing, reason: '이미 동의한 사람이다');
    expect(find.text('보리 저녁밥 줬어요'), findsOneWidget, reason: '방이 열려 있다');
    expect(_noticeButton, findsOneWidget);
  });

  testWidgets('안내 버튼을 누르면 주의 · 제재 문구가 그 자리에서 다시 뜬다', (tester) async {
    await _openRoom(tester);

    await tester.tap(_noticeButton);
    await tester.pumpAndSettle();

    expect(find.text('채팅 이용 안내'), findsOneWidget);
    expect(find.text(ChatTermsDialog.safetyTitle), findsOneWidget);
    for (final line in ChatTermsDialog.safety) {
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('다시 보기는 동의를 다시 받지 않는다 — 닫으면 방으로 돌아온다', (tester) async {
    await _openRoom(tester);

    await tester.tap(_noticeButton);
    await tester.pumpAndSettle();

    expect(find.text('동의하고 시작'), findsNothing);
    expect(find.text('나중에'), findsNothing);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(find.text('채팅 이용 안내'), findsNothing);
    expect(find.text('보리 저녁밥 줬어요'), findsOneWidget, reason: '방을 떠나지 않는다');
    expect(
      await const ChatTermsGate().hasAgreed(42),
      isTrue,
      reason: '읽기만 한 것이 동의 기록을 건드리면 안 된다',
    );
  });

  testWidgets('방 이름이 길어도 안내 버튼이 밀려나지 않는다', (tester) async {
    await const ChatTermsGate().markAgreed(42);
    await tester.pumpWidget(MaterialApp(
      home: FamilyChatScreen(
        roomId: 7,
        title: '보리 누나네 옆집 산책 친구들 아침 모임 단톡방',
        subtitle: '멤버 8명 · 오늘 아침 7시에 만나요',
        repository: _repo(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '머리말이 넘치면 안 된다');
    expect(_noticeButton, findsOneWidget);
  });
}

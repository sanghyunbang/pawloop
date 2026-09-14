// 채팅 탭의 안 읽음 점 — 이슈 #452. 점 하나이지 개수가 아니고, 음소거한 방은 안 켠다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/chat_unread.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';

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

class _FakeChatRepo extends ChatRepository {
  List<ChatRoomSummary> next = const [];
  int calls = 0;

  _FakeChatRepo()
      : super(
          baseUrl: 'http://unused',
          client: AuthedClient(
            inner: MockClient((_) async => http.Response('[]', 200)),
            baseUrl: 'http://unused',
            store: _NoTokens(),
          ),
        );

  @override
  Future<List<ChatRoomSummary>> rooms() async {
    calls++;
    return next;
  }
}

ChatRoomSummary _room(int id, {int unread = 0, bool muted = false}) => ChatRoomSummary(
      id: id,
      title: '방 $id',
      tag: '가족',
      lastSeq: 10,
      lastReadSeq: 10 - unread,
      unread: unread,
      memberCount: 2,
      muted: muted,
    );

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: MainShell()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyDog.value = null;
    kMyPets.value = const [];
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    ChatUnread.resetForTest();
  });
  tearDown(() {
    AuthState.resetForTest();
    ChatUnread.resetForTest();
  });

  testWidgets('탭 바: 안 읽은 방이 있으면 채팅 아이콘에 점 하나, 없으면 없다 — 개수는 안 쓴다', (tester) async {
    await _pumpShell(tester);
    expect(find.byKey(const Key('chat-unread-dot')), findsNothing);

    ChatUnread.any.value = true;
    await tester.pump();
    final dot = find.byKey(const Key('chat-unread-dot'));
    expect(dot, findsOneWidget);
    expect(tester.getSize(dot).width, lessThan(12), reason: '점이지 숫자 뱃지가 아니다');
    expect(find.descendant(of: dot, matching: find.byType(Text)), findsNothing);

    ChatUnread.any.value = false;
    await tester.pump();
    expect(find.byKey(const Key('chat-unread-dot')), findsNothing);
  });

  testWidgets('감시자: 로그인한 동안 주기마다 방 목록을 보고 점을 켜고 끈다 — 음소거한 방은 안 센다', (tester) async {
    AuthState.status.value = AuthStatus.authenticated;
    final repo = _FakeChatRepo()..next = [_room(1, unread: 2), _room(2)];

    await tester.pumpWidget(MaterialApp(
        home: ChatUnreadWatcher(repository: repo, interval: const Duration(seconds: 1))));
    await tester.pump();
    expect(repo.calls, 1, reason: '켜지자마자 한 번 본다');
    expect(ChatUnread.any.value, isTrue);

    repo.next = [_room(1), _room(2)];
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.calls, 2, reason: '1초 주기로 다시 본다');
    expect(ChatUnread.any.value, isFalse);

    repo.next = [_room(1, unread: 3, muted: true)];
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.calls, 3);
    expect(ChatUnread.any.value, isFalse, reason: '음소거한 방의 안 읽음은 탭을 안 켠다');

    await tester.pumpWidget(const SizedBox()); // 감시자를 내려 타이머를 끈다.
  });

  testWidgets('감시자: 게스트는 서버를 안 부르고, 로그인하면 바로 보고, 나가면 점이 꺼진다', (tester) async {
    final repo = _FakeChatRepo()..next = [_room(1, unread: 1)];
    await tester.pumpWidget(MaterialApp(
        home: ChatUnreadWatcher(repository: repo, interval: const Duration(minutes: 5))));
    await tester.pump();
    expect(repo.calls, 0, reason: '게스트는 방이 없는 게 아니라 계정이 없다 — 부르지 않는다');
    expect(ChatUnread.any.value, isFalse);

    AuthState.status.value = AuthStatus.authenticated;
    await tester.pump();
    expect(repo.calls, 1);
    expect(ChatUnread.any.value, isTrue);

    AuthState.status.value = AuthStatus.unauthenticated;
    await tester.pump();
    expect(ChatUnread.any.value, isFalse, reason: '나가면 남의 점이 남지 않는다');
    expect(repo.calls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  test('서버의 muted 를 읽는다 — 없으면 false', () {
    final base = {'id': 7, 'title': '방', 'tag': '가족', 'lastSeq': 3, 'lastReadSeq': 0, 'unread': 3, 'memberCount': 2};
    expect(ChatRoomSummary.tryParse({...base, 'muted': true})!.muted, isTrue);
    expect(ChatRoomSummary.tryParse({...base, 'muted': false})!.muted, isFalse);
    expect(ChatRoomSummary.tryParse(base)!.muted, isFalse);
    // 음소거한 방 하나뿐이면 점이 안 켜진다 — 파싱과 판정을 이어서.
    ChatUnread.update([ChatRoomSummary.tryParse({...base, 'muted': true})!]);
    expect(ChatUnread.any.value, isFalse);
    ChatUnread.update([ChatRoomSummary.tryParse(base)!]);
    expect(ChatUnread.any.value, isTrue);
  });

  testWidgets('방 목록 화면이 받은 답으로도 점이 갱신된다', (tester) async {
    AuthState.status.value = AuthStatus.authenticated;
    final repo = _FakeChatRepo()..next = [_room(1, unread: 1)];

    await tester.pumpWidget(MaterialApp(home: ChatListScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('방 1'), findsOneWidget);
    expect(ChatUnread.any.value, isTrue);

    repo.next = [_room(1)];
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(ChatUnread.any.value, isFalse, reason: '다시 받으면 서버 답대로 꺼진다');
  });
}

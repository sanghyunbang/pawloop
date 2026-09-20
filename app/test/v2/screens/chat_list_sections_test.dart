// 채팅 목록의 구분 — 이슈 #730.
//
// 사장님 질문: 내가 만든 가족과 내가 참여하는 크루가 사용자 관점에서 나뉘어 있나. 예전에는 한 목록에
// 최근 대화순이라 크루 방이 가족 방 위로 올라갔다. 여기서 재는 것 넷.
//   - 가족 방은 대화가 없어도 **맨 위**다 — 크루 방에 더 새 말이 있어도
//   - 가족 방 아래에 '참여 중인 크루 · 이웃' 소제목이 **한 번** 있다
//   - 내가 만든 크루 줄에 `방장` 칩이 있고, 가족 방과 남의 크루에는 없다
//   - 가족 방뿐이면 소제목이 없다 — 나눌 것이 없는데 제목만 있으면 빈 칸을 가리킨다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/screens/chat_list_screen.dart';

const _base = 'https://api.example.test';

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';
  @override
  Future<String?> readRefreshToken() async => 'RT-1';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

String _room(int id, String title, {String tag = '가족', String role = 'MEMBER', String? at}) =>
    '{"id":$id,"title":"$title","tag":"$tag","lastSeq":3,"lastReadSeq":3,"unread":0,"memberCount":2,"myRole":"$role","muted":false'
    '${at == null ? '' : ',"lastMessage":{"id":9,"roomId":$id,"roomSeq":3,"senderUserId":8,"senderName":"보리아빠","contentType":"text","body":"저녁 산책 갈까요?","createdAt":"$at","hiddenByBlock":false}'}'
    '}';

ChatRepository _repo(String rooms) => ChatRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((request) async => http.Response(rooms, 200,
            headers: const {'content-type': 'application/json; charset=utf-8'})),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

Future<void> _pump(WidgetTester tester, String rooms) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ChatListScreen(repository: _repo(rooms))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker')));
  tearDown(AuthState.resetForTest);

  final today = DateTime.now().toUtc().toIso8601String();

  testWidgets('가족 방은 대화가 없어도 맨 위 — 크루 방에 더 새 말이 있어도', (tester) async {
    // 서버 순서는 최근 대화순: 크루(오늘 말 있음)가 먼저 온다.
    await _pump(tester, '[${_room(2, "성수 아침 크루", tag: "크루", role: "OWNER", at: today)},${_room(1, "우리 가족")}]');

    final family = tester.getTopLeft(find.byKey(const Key('room-card-1')));
    final crew = tester.getTopLeft(find.byKey(const Key('room-card-2')));
    expect(family.dy, lessThan(crew.dy), reason: '가족 방은 집의 허브라 대화순에 밀리면 안 된다(#730)');
  });

  testWidgets("가족 방 아래에 '참여 중인 크루 · 이웃' 소제목이 한 번 있다", (tester) async {
    await _pump(tester,
        '[${_room(2, "성수 아침 크루", tag: "크루", at: today)},${_room(1, "우리 가족")},${_room(3, "옆집", tag: "이웃")}]');

    expect(find.byKey(const Key('chat-others-title')), findsOneWidget);
    expect(find.text('참여 중인 크루 · 이웃'), findsOneWidget);
    final title = tester.getTopLeft(find.byKey(const Key('chat-others-title')));
    expect(title.dy, greaterThan(tester.getTopLeft(find.byKey(const Key('room-card-1'))).dy));
    expect(title.dy, lessThan(tester.getTopLeft(find.byKey(const Key('room-card-2'))).dy));
  });

  testWidgets('내가 만든 크루에만 방장 칩 — 가족 방과 남의 크루에는 없다', (tester) async {
    await _pump(tester,
        '[${_room(1, "우리 가족", role: "OWNER")},${_room(2, "내 크루", tag: "크루", role: "OWNER")},${_room(3, "남의 크루", tag: "크루")}]');

    expect(find.byKey(const Key('room-owner-2')), findsOneWidget);
    expect(find.byKey(const Key('room-owner-1')), findsNothing, reason: '가족 방은 누구나 관리로 간다');
    expect(find.byKey(const Key('room-owner-3')), findsNothing);
    expect(find.text('방장'), findsOneWidget);
  });

  testWidgets('가족 방뿐이면 소제목이 없다', (tester) async {
    await _pump(tester, '[${_room(1, "우리 가족")}]');

    expect(find.byKey(const Key('room-card-1')), findsOneWidget);
    expect(find.byKey(const Key('chat-others-title')), findsNothing);
  });
}

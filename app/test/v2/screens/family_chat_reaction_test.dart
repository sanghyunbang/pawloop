// 말풍선 아래 반응 줄 (#452) — 숫자가 보이고, 눌러서 켜고 끄고, 남이 누른 것은 변경 피드로 온다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_chat_screen.dart';

import '../support/fake_media_picker.dart';

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

http.StreamedResponse _json(String body, int status) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _msg(int seq, String body, {String reactions = '[]'}) =>
    '{"id":$seq,"roomId":4,"roomSeq":$seq,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"$body","createdAt":"2026-09-15T07:0$seq:00Z","hiddenByBlock":false,'
    '"reactions":$reactions}';

/// 첫 장에 말 하나. 반응을 켜고 끄는 요청을 받아 적고, 그다음 폴링부터 [changedReactions] 를 흘린다.
class _Server {
  _Server({this.firstReactions = '[]'});

  final String firstReactions;
  final List<http.BaseRequest> writes = [];
  String? changedReactions;

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      final path = request.url.path;
      if (path.endsWith('/read')) return _json('{}', 200);
      if (path.contains('/reactions/')) {
        writes.add(request);
        // 서버는 그 말의 **최신 집계 전부**를 돌려준다 — 누른 종류 하나가 아니다.
        final kind = request.url.pathSegments.last;
        final on = request.method == 'POST';
        return _json('{"messageId":1,"reactions":['
            '{"kind":"like","count":9,"mine":${kind == 'like' ? on : false}},'
            '{"kind":"check","count":1,"mine":${kind == 'check' ? on : true}}]}', 200);
      }
      if (changedReactions != null) {
        return _json('{"items":[],"lastSeq":1,"hasMore":false,'
            '"changed":[${_msg(1, "보리 밥 줬어요", reactions: changedReactions!)}],"lastChangeSeq":7}', 200);
      }
      return _json('{"items":[${_msg(1, "보리 밥 줬어요", reactions: firstReactions)}],'
          '"lastSeq":1,"hasMore":false,"changed":[],"lastChangeSeq":0}', 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
}

Future<PreparedImage> _fakePrepare(Uint8List original) async =>
    PreparedImage(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]), width: 1200, height: 1600);

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(
      roomId: 4,
      repository: ChatRepository(baseUrl: _base, client: server.client),
      media: PostMediaRepository(baseUrl: _base, client: server.client),
      picker: FakeMediaPicker((_) => const []),
      prepare: _fakePrepare,
    ),
  ));
  await tester.pumpAndSettle();
}

/// 다음 폴링이 돌 때까지 — 정책의 첫 간격은 몇 초라 넉넉히 민다.
Future<void> _nextPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('반응이 있는 말에는 아래에 칩이 뜬다 — 숫자가 있는 종류만', (tester) async {
    final server = _Server(
        firstReactions: '[{"kind":"like","count":2,"mine":false},{"kind":"check","count":1,"mine":true}]');
    await _pump(tester, server);

    expect(find.byKey(const Key('chat-reaction-1-like')), findsOneWidget);
    expect(find.byKey(const Key('chat-reaction-1-check')), findsOneWidget);
    expect(find.byKey(const Key('chat-reaction-1-sad')), findsNothing,
        reason: '아무도 안 누른 종류까지 그리면 말마다 다섯 칸이 붙는다');
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('안 누른 칩을 누르면 켜기(POST), 누른 칩을 누르면 끄기(DELETE)', (tester) async {
    final server = _Server(
        firstReactions: '[{"kind":"like","count":2,"mine":false},{"kind":"check","count":1,"mine":true}]');
    await _pump(tester, server);

    await tester.tap(find.byKey(const Key('chat-reaction-1-like')));
    await tester.pumpAndSettle();
    expect(server.writes.single.method, 'POST');
    expect(server.writes.single.url.path, '/api/chat/messages/1/reactions/like');

    await tester.tap(find.byKey(const Key('chat-reaction-1-check')));
    await tester.pumpAndSettle();
    expect(server.writes.last.method, 'DELETE',
        reason: '이미 누른 것을 또 누르면 취소다 — 같은 자리에서 켰으니 같은 자리가 끈다');
    expect(server.writes.last.url.path, '/api/chat/messages/1/reactions/check');
  });

  testWidgets('누르면 돌아온 집계를 그 말풍선에 바로 그린다 — 다음 폴링을 기다리지 않는다', (tester) async {
    final server = _Server(firstReactions: '[{"kind":"like","count":2,"mine":false}]');
    await _pump(tester, server);

    await tester.tap(find.byKey(const Key('chat-reaction-1-like')));
    await tester.pumpAndSettle();

    expect(find.text('9'), findsOneWidget, reason: '서버가 준 최신 집계다 — 앱이 1 을 더하면 남이 누른 것을 못 본다');
  });

  testWidgets('남이 누른 반응이 changed 로 와서 같은 자리에 붙는다 — 말풍선이 하나 더 안 생긴다', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    expect(find.byKey(const Key('chat-reaction-1-heart')), findsNothing);

    server.changedReactions = '[{"kind":"heart","count":1,"mine":false}]';
    await _nextPoll(tester);

    expect(find.byKey(const Key('chat-reaction-1-heart')), findsOneWidget,
        reason: '반응은 room_seq 를 안 올린다 — 변경 피드를 타야 남의 화면에 닿는다(ADR-0023)');
    expect(find.text('보리 밥 줬어요'), findsOneWidget, reason: '같은 말이 두 번 그려지면 안 된다');
    expect(find.byKey(const Key('chat-new-messages')), findsNothing,
        reason: '반응은 새 메시지가 아니다');
  });

  testWidgets('길게 눌러 고른 반응이 그 말에 켜진다', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await tester.longPress(find.text('보리 밥 줬어요'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reaction-pick-like')));
    await tester.pumpAndSettle();

    expect(server.writes.single.method, 'POST');
    expect(server.writes.single.url.path, '/api/chat/messages/1/reactions/like');
    expect(find.byKey(const Key('chat-reaction-1-like')), findsOneWidget);
  });
}

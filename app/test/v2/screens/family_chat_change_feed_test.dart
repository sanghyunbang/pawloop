// 남이 지운 말이 폴링에 따라온다 (ADR-0023, #500) — 같은 자리가 바뀌고, 대화 맨 아래로 올라오지 않는다.
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

String _msg(int seq, String body, {String? deletedAt}) =>
    '{"id":$seq,"roomId":4,"roomSeq":$seq,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"$body","createdAt":"2026-09-15T07:0$seq:00Z","hiddenByBlock":false'
    '${deletedAt == null ? '' : ',"deletedAt":"$deletedAt"'}}';

/// 첫 장에는 말 둘, 그다음 폴링부터는 첫 말이 지워졌다고 알려 준다.
class _Server {
  final List<Uri> polls = [];
  bool deletedYet = false;

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      if (request.url.path.endsWith('/read')) return _json('{}', 200);
      polls.add(request.url);
      if (!deletedYet) {
        return _json('{"items":[${_msg(1, "지울 말")},${_msg(2, "남을 말")}],'
            '"lastSeq":2,"hasMore":false,"changed":[],"lastChangeSeq":0}', 200);
      }
      return _json('{"items":[],"lastSeq":2,"hasMore":false,'
          '"changed":[${_msg(1, "", deletedAt: "2026-09-15T07:30:00Z")}],"lastChangeSeq":4}', 200);
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

  testWidgets('남이 지운 말이 같은 자리에서 "삭제된 메시지예요" 가 된다 — 말풍선이 하나 더 생기지 않는다', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    expect(find.text('지울 말'), findsOneWidget);
    expect(find.text('남을 말'), findsOneWidget);

    server.deletedYet = true;
    await _nextPoll(tester);

    expect(find.text('지울 말'), findsNothing, reason: '같은 자리가 톰스톤으로 바뀐다');
    expect(find.text('삭제된 메시지예요'), findsOneWidget);
    expect(find.text('남을 말'), findsOneWidget, reason: '나머지는 그대로다');
  });

  testWidgets('첫 진입은 afterChangeSeq 를 안 보내고, 그다음부터 서버가 준 커서를 되돌려 보낸다', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    expect(server.polls.first.queryParameters.containsKey('afterChangeSeq'), isFalse,
        reason: '첫 장은 이미 최신이다');

    await _nextPoll(tester);
    expect(server.polls[1].queryParameters['afterChangeSeq'], '0');

    server.deletedYet = true;
    await _nextPoll(tester); // 여기서 lastChangeSeq 4 를 받는다
    await _nextPoll(tester);

    expect(server.polls.last.queryParameters['afterChangeSeq'], '4',
        reason: '받은 커서를 그대로 되돌려 보내야 같은 변화를 두 번 받지 않는다');
  });

  testWidgets('바뀐 말은 "새 메시지" 가 아니다 — 알약이 뜨지 않는다', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    server.deletedYet = true;
    await _nextPoll(tester);

    expect(find.byKey(const Key('chat-new-messages')), findsNothing,
        reason: '지워진 것은 새 소식이 아니다');
  });
}

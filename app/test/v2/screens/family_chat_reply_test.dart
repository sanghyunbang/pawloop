// 채팅방 답장 (#452) — 길게 눌러 "답장" → 입력창 위 인용 띠 → 보낸 말풍선 안 인용 블록. 서버는 가짜(MockClient).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/chat_terms_gate.dart';
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

/// 서버 흉내 — 목록과 전송. 전송 본문에 `replyToId` 가 있으면 계약대로 `replyTo` 미리보기를 실어 돌려준다.
class _Server {
  final List<Map<String, dynamic>> sends = [];
  int sendFailuresLeft = 0;
  String items = '[]';

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      final body = await bodyStream.bytesToString();
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/messages')) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        sends.add(json);
        if (sendFailuresLeft > 0) {
          sendFailuresLeft--;
          throw Exception('connection reset');
        }
        final replyTo = json['replyToId'] == null
            ? 'null'
            : '{"id":${json['replyToId']},"senderName":"보통 사람","preview":"저녁 산책 갈까요?","deleted":false}';
        return _json(
            '{"id":9,"roomId":4,"roomSeq":${sends.length + 3},"senderUserId":1,"senderName":"나","contentType":"text",'
            '"body":"${json['body']}","createdAt":"2026-09-14T07:05:00Z","hiddenByBlock":false,"replyTo":$replyTo}',
            201);
      }
      if (path.endsWith('/read')) return _json('{}', 200);
      return _json('{"items":$items,"lastSeq":3,"hasMore":false}', 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
}

/// 온 말 셋 — 원문(1) · 그 원문에 대한 답장(2) · 지워진 말(3). 전부 남(8)의 말이다.
const _incoming = '['
    '{"id":1,"roomId":4,"roomSeq":1,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"저녁 산책 갈까요?","createdAt":"2026-09-14T07:00:00Z","hiddenByBlock":false},'
    '{"id":2,"roomId":4,"roomSeq":2,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"7시 어때요","createdAt":"2026-09-14T07:01:00Z","hiddenByBlock":false,'
    '"replyTo":{"id":1,"senderName":"보통 사람","preview":"저녁 산책 갈까요?","deleted":false}},'
    '{"id":3,"roomId":4,"roomSeq":3,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"지운 말","createdAt":"2026-09-14T07:02:00Z","deletedAt":"2026-09-14T07:03:00Z","hiddenByBlock":false}'
    ']';

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

/// 원문(1)의 말풍선을 길게 눌러 "답장" 을 고른다. 같은 글자가 답장(2)의 인용에도 있어 첫째 것을 고른다.
Future<void> _chooseReply(WidgetTester tester) async {
  await tester.longPress(find.text('저녁 산책 갈까요?').first);
  await tester.pumpAndSettle();
  expect(find.text('답장'), findsOneWidget, reason: '메뉴 첫 줄이 답장이다');
  await tester.tap(find.text('답장'));
  await tester.pumpAndSettle();
}

Finder _pendingQuote() => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('chat-reply-quote-pending-'));

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('온 답장은 말풍선 안에 원문의 이름과 첫 줄을 인용한다 — 원문 자체에는 인용이 없다', (tester) async {
    final server = _Server()..items = _incoming;
    await _pump(tester, server);

    final quote = find.byKey(const Key('chat-reply-quote-2'));
    expect(quote, findsOneWidget);
    expect(find.descendant(of: quote, matching: find.text('보통 사람')), findsOneWidget);
    expect(find.descendant(of: quote, matching: find.text('저녁 산책 갈까요?')), findsOneWidget);
    expect(find.byKey(const Key('chat-reply-quote-1')), findsNothing);
  });

  testWidgets('길게 눌러 답장 → 입력창 위 인용 띠 → 보내면 replyToId 가 실리고 띠는 사라지고 말풍선에 인용이 남는다',
      (tester) async {
    final server = _Server()..items = _incoming;
    await _pump(tester, server);

    await _chooseReply(tester);

    expect(find.byKey(const Key('chat-reply-bar')), findsOneWidget);
    expect(find.text('보통 사람에게 답장'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '좋아요');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(server.sends.single['replyToId'], 1);
    expect(server.sends.single['body'], '좋아요');
    expect(find.byKey(const Key('chat-reply-bar')), findsNothing, reason: '보내면 띠가 사라진다');
    final confirmed = find.byKey(const Key('chat-reply-quote-9'));
    expect(confirmed, findsOneWidget, reason: '서버가 확정한 말풍선에 인용이 있다');
    expect(find.descendant(of: confirmed, matching: find.text('저녁 산책 갈까요?')), findsOneWidget);
  });

  testWidgets('전송이 끊겨도 보내는 중 말풍선이 인용을 들고 있다 — 다시 보내기도 같은 원문으로', (tester) async {
    final server = _Server()
      ..items = _incoming
      ..sendFailuresLeft = 1;
    await _pump(tester, server);

    await _chooseReply(tester);
    await tester.enterText(find.byType(TextField), '좋아요');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(_pendingQuote(), findsOneWidget, reason: '확정 전에도 인용을 그린다');
    expect(find.text('보내지 못했어요 · 다시 보내기'), findsOneWidget);

    await tester.tap(find.text('보내지 못했어요 · 다시 보내기'));
    await tester.pumpAndSettle();

    expect(server.sends.map((s) => s['replyToId']), [1, 1]);
    expect(find.byKey(const Key('chat-reply-quote-9')), findsOneWidget);
  });

  testWidgets('띠의 닫기를 누르면 답장이 아니다 — 다음 전송에 replyToId 가 없다', (tester) async {
    final server = _Server()..items = _incoming;
    await _pump(tester, server);

    await _chooseReply(tester);
    await tester.tap(find.byKey(const Key('chat-reply-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-reply-bar')), findsNothing);

    await tester.enterText(find.byType(TextField), '그냥 말');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(server.sends.single.containsKey('replyToId'), isFalse);
    expect(find.byKey(const Key('chat-reply-quote-9')), findsNothing);
  });

  testWidgets('지워진 말에는 답장이 없다', (tester) async {
    final server = _Server()..items = _incoming;
    await _pump(tester, server);

    await tester.longPress(find.text('삭제된 메시지예요'));
    await tester.pumpAndSettle();

    expect(find.text('신고하기'), findsOneWidget, reason: '메뉴는 뜬다');
    expect(find.text('답장'), findsNothing);
  });

  testWidgets('내 말도 길게 눌러 답장할 수 있다 — 띠는 "나에게 답장"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await const ChatTermsGate().markAgreed(8);
    AuthState.signInForTest(const AuthUser(id: 8, nickname: '보통 사람'));
    final server = _Server()..items = _incoming;
    await _pump(tester, server);

    await tester.longPress(find.text('저녁 산책 갈까요?').first);
    await tester.pumpAndSettle();

    expect(find.text('답장'), findsOneWidget);
    expect(find.text('이 메시지 삭제'), findsOneWidget, reason: '내 말의 메뉴는 답장과 삭제다');
    await tester.tap(find.text('답장'));
    await tester.pumpAndSettle();

    expect(find.text('나에게 답장'), findsOneWidget);
  });
}

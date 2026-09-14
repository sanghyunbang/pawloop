// 인용을 누르면 원문으로 (#452) — 화면 밖의 원문까지 올라가 찾고, 잠깐 물들고, 이 장에 없으면 그렇다고 말한다.
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

/// 남(8)의 말 [count] 개. 마지막 말은 첫 말(id 1)에 대한 답장이다 — 원문은 화면 밖에 있다.
String _thread(int count) {
  final items = <String>[];
  for (var i = 1; i <= count; i++) {
    final at = '2026-09-14T07:${i.toString().padLeft(2, '0')}:00Z';
    final reply = i == count
        ? ',"replyTo":{"id":1,"senderName":"보통 사람","preview":"저녁 산책 갈까요?","deleted":false}'
        : '';
    items.add('{"id":$i,"roomId":4,"roomSeq":$i,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
        '"body":"${i == 1 ? '저녁 산책 갈까요?' : '말 $i'}","createdAt":"$at","hiddenByBlock":false$reply}');
  }
  return '[${items.join(',')}]';
}

class _Server {
  _Server(this.items);
  final String items;

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      if (request.url.path.endsWith('/read')) return _json('{}', 200);
      return _json('{"items":$items,"lastSeq":30,"hasMore":false}', 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
}

Future<PreparedImage> _fakePrepare(Uint8List original) async =>
    PreparedImage(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]), width: 1200, height: 1600);

/// 창을 작게 둔다 — 원문(첫 말)이 화면 밖에 있어야 "올라가며 찾기" 를 실제로 잰다.
Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(600, 900);
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

/// 원문 줄(첫 말)의 **본문**. 답장의 인용 미리보기가 같은 글자를 쓰므로(원문의 첫 줄이다) 글자 크기로 가른다 —
/// 말풍선 본문은 13.5, 인용 미리보기는 11.5 다.
Finder _originalBody() => find.byWidgetPredicate(
    (w) => w is Text && w.data == '저녁 산책 갈까요?' && (w.style?.fontSize ?? 0) > 12);

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('인용을 누르면 화면 밖의 원문까지 올라가 보여 주고, 그 줄이 잠깐 물든다', (tester) async {
    await _pump(tester, _Server(_thread(25)));

    // 처음에는 바닥이라 원문이 안 보인다.
    expect(_originalBody().hitTestable(), findsNothing);

    await tester.tap(find.byKey(const Key('chat-reply-quote-25')));
    await tester.pumpAndSettle();

    expect(_originalBody().hitTestable(), findsOneWidget, reason: '원문이 화면에 들어왔다');
    final tinted = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color != null && d.color!.a > 0;
    });
    expect(tinted, isNotEmpty, reason: '찾아간 줄이 물든다');

    // 잠깐이다 — 시간이 지나면 다시 투명해진다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final stillTinted = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color != null && d.color!.a > 0;
    });
    expect(stillTinted, isEmpty, reason: '강조가 남아 있으면 새 말처럼 보인다');
  });

  testWidgets('이 장에 없는 원문이면 그렇다고 말한다 — 조용히 아무 일도 안 하지 않는다', (tester) async {
    // 답장 하나만 온 장 — 그 답장이 가리키는 id 1 은 아직 안 불러왔다.
    const only = '[{"id":9,"roomId":4,"roomSeq":9,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
        '"body":"7시 어때요","createdAt":"2026-09-14T07:09:00Z","hiddenByBlock":false,'
        '"replyTo":{"id":1,"senderName":"보통 사람","preview":"저녁 산책 갈까요?","deleted":false}}]';
    await _pump(tester, _Server(only));

    await tester.tap(find.byKey(const Key('chat-reply-quote-9')));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 안 불러왔어요'), findsOneWidget);
  });

  testWidgets('바로 위의 원문은 올라가지 않고 그 자리에서 물든다', (tester) async {
    await _pump(tester, _Server(_thread(3)));

    await tester.tap(find.byKey(const Key('chat-reply-quote-3')));
    await tester.pumpAndSettle();

    expect(_originalBody().hitTestable(), findsOneWidget);
    expect(find.textContaining('아직 안 불러왔어요'), findsNothing);
  });
}

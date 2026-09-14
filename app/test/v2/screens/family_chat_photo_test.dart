// 말풍선 사진 — 이슈 #452. 받은 사진은 4:5 규칙으로 그리고, 보내는 사진은 올리고(CHAT_IMAGE) → 전송한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/image_prep.dart';
import 'package:heat_trip_flutter/v2/data/media_picker.dart';
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

/// 서버 흉내 — 목록 · 올리기 · 전송 · 읽음. 무엇이 왔는지 기록한다.
class _Server {
  final List<String> uploads = [];
  final List<Map<String, dynamic>> sends = [];
  int uploadFailuresLeft = 0;
  int sendFailuresLeft = 0;
  String items = '[]';

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      if (request is http.MultipartRequest) {
        await bodyStream.drain<void>();
        uploads.add(request.fields['category'] ?? '?');
        if (uploadFailuresLeft > 0) {
          uploadFailuresLeft--;
          return _json('{"error":{"code":"INTERNAL","message":"버킷이 아프다"}}', 500);
        }
        return _json(
            '[{"id":31,"key":"chats/1/a.jpg","url":"https://cdn/chats/a.jpg","category":"CHAT_IMAGE","status":"ready"}]',
            200);
      }
      final body = await bodyStream.bytesToString();
      final path = request.url.path;
      if (request.method == 'POST' && path.endsWith('/messages')) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        sends.add(json);
        if (sendFailuresLeft > 0) {
          sendFailuresLeft--;
          throw Exception('connection reset');
        }
        return _json(
            '{"id":9,"roomId":4,"roomSeq":${sends.length + 2},"senderUserId":1,"senderName":"나","contentType":"image",'
            '"body":"","createdAt":"2026-09-14T07:05:00Z","hiddenByBlock":false,'
            '"media":{"id":${json['mediaId']},"kind":"image","url":"https://cdn/chats/a.jpg","width":1200,"height":1600}}',
            201);
      }
      if (path.endsWith('/read')) return _json('{}', 200);
      return _json('{"items":$items,"lastSeq":2,"hasMore":false}', 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
}

const _incoming = '['
    '{"id":1,"roomId":4,"roomSeq":1,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"글자 말","createdAt":"2026-09-14T07:00:00Z","hiddenByBlock":false},'
    '{"id":2,"roomId":4,"roomSeq":2,"senderUserId":8,"senderName":"보통 사람","contentType":"image",'
    '"body":"","createdAt":"2026-09-14T07:01:00Z","hiddenByBlock":false,'
    '"media":{"id":17,"kind":"image","url":"https://cdn/chats/tall.jpg","width":720,"height":1280}}'
    ']';

Future<PreparedImage> _fakePrepare(Uint8List original) async =>
    PreparedImage(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]), width: 1200, height: 1600);

Future<void> _pump(WidgetTester tester, _Server server, {FakeMediaPicker? picker}) async {
  // 사진 말풍선은 키가 크다 — 기본 창(600dp)에서는 위의 글자 말풍선이 밀려 안 그려진다.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(
      roomId: 4,
      repository: ChatRepository(baseUrl: _base, client: server.client),
      media: PostMediaRepository(baseUrl: _base, client: server.client),
      picker: picker ?? FakeMediaPicker((_) => const []),
      prepare: _fakePrepare,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('받은 사진 메시지는 사진 말풍선이고 세로 사진은 4:5 까지 — 글자 메시지에는 사진이 없다', (tester) async {
    final server = _Server()..items = _incoming;

    await _pump(tester, server);

    expect(find.byKey(const Key('chat-photo-2')), findsOneWidget);
    expect(find.byKey(const Key('chat-photo-1')), findsNothing);
    final ratio = tester.widget<AspectRatio>(find.descendant(
        of: find.byKey(const Key('chat-photo-2')), matching: find.byType(AspectRatio)));
    expect(ratio.aspectRatio, closeTo(0.8, 0.001), reason: '720×1280(9:16)은 커뮤니티 카드와 같은 4:5 로 자른다');
    expect(find.text('글자 말'), findsOneWidget);
  });

  testWidgets('사진 버튼 → 고른 사진을 CHAT_IMAGE 로 올리고 mediaId 로 보낸다 — 본문은 비고 종류는 image', (tester) async {
    final server = _Server();
    final picker = FakeMediaPicker((_) => [PickedImage(name: 'p.jpg', bytes: Uint8List.fromList([1, 2, 3]))]);

    await _pump(tester, server, picker: picker);
    await tester.tap(find.byKey(const Key('chat-photo')));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, 10, reason: '열 장까지 — 사진 하나에 메시지 하나');
    expect(server.uploads, ['CHAT_IMAGE']);
    expect(server.sends.single['mediaId'], 31);
    expect(server.sends.single['contentType'], 'image');
    expect(server.sends.single['body'], '');
    expect(find.byKey(const Key('chat-photo-9')), findsOneWidget, reason: '서버가 확정한 사진 말풍선');
    expect(find.byKey(Key('chat-photo-pending-${server.sends.single['clientMsgId']}')), findsNothing,
        reason: '확정되면 대기 사진은 빠진다');
  });

  testWidgets('올리기가 실패하면 그 자리에 남고 "다시 보내기" 가 다시 올린다', (tester) async {
    final server = _Server()..uploadFailuresLeft = 1;
    final picker = FakeMediaPicker((_) => [PickedImage(name: 'p.jpg', bytes: Uint8List.fromList([1]))]);

    await _pump(tester, server, picker: picker);
    await tester.tap(find.byKey(const Key('chat-photo')));
    await tester.pumpAndSettle();

    expect(find.text('보내지 못했어요 · 다시 보내기'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('chat-photo-pending-')),
        findsOneWidget,
        reason: '사진은 사라지지 않는다');
    expect(server.sends, isEmpty, reason: '못 올렸으면 전송도 안 한다');

    await tester.tap(find.text('보내지 못했어요 · 다시 보내기'));
    await tester.pumpAndSettle();

    expect(server.uploads, hasLength(2));
    expect(server.sends.single['mediaId'], 31);
    expect(find.byKey(const Key('chat-photo-9')), findsOneWidget);
  });

  testWidgets('올렸는데 전송이 끊기면 다시 보내기는 올리지 않고 전송만 — 같은 사진이 버킷에 두 번 남지 않는다', (tester) async {
    final server = _Server()..sendFailuresLeft = 1;
    final picker = FakeMediaPicker((_) => [PickedImage(name: 'p.jpg', bytes: Uint8List.fromList([1]))]);

    await _pump(tester, server, picker: picker);
    await tester.tap(find.byKey(const Key('chat-photo')));
    await tester.pumpAndSettle();

    expect(server.uploads, hasLength(1));
    expect(find.text('보내지 못했어요 · 다시 보내기'), findsOneWidget);

    await tester.tap(find.text('보내지 못했어요 · 다시 보내기'));
    await tester.pumpAndSettle();

    expect(server.uploads, hasLength(1), reason: '올린 id 를 들고 있으니 다시 올리지 않는다');
    expect(server.sends, hasLength(2));
    expect(server.sends.map((s) => s['clientMsgId']).toSet(), hasLength(1), reason: '같은 멱등키');
    expect(server.sends.last['mediaId'], 31);
    expect(find.byKey(const Key('chat-photo-9')), findsOneWidget);
  });
}

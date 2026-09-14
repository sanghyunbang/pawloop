// 채팅방 읽기 흐름 (#452) — 묶인 말풍선 · 날짜 구분선 · "새 메시지 N개" 알약.
//
// 서버는 가짜(MockClient). 로그인은 없어서(`AuthState.user == null`) 온 말은 전부 남의 말이다 —
// 알약은 남의 말에만 뜨므로 그 조건을 그대로 쓴다.
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

/// 메시지 하나의 JSON. [seq] 가 곧 id 다.
String _msg(int seq, String who, int userId, String body, String at) =>
    '{"id":$seq,"roomId":4,"roomSeq":$seq,"senderUserId":$userId,"senderName":"$who","contentType":"text",'
    '"body":"$body","createdAt":"$at","hiddenByBlock":false}';

class _Server {
  /// 폴링마다 돌려줄 목록. 화면은 `afterSeq` 뒤의 것만 새것으로 친다.
  String items = '[]';
  int polls = 0;

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      final path = request.url.path;
      if (path.endsWith('/read')) return _json('{}', 200);
      polls++;
      return _json('{"items":$items,"lastSeq":0,"hasMore":false}', 200);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
}

Future<PreparedImage> _fakePrepare(Uint8List original) async =>
    PreparedImage(bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]), width: 1200, height: 1600);

Future<void> _pump(WidgetTester tester, _Server server, {Size size = const Size(800, 1600)}) async {
  tester.view.physicalSize = size;
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
  testWidgets('같은 사람의 같은 분은 한 묶음 — 이름 · 아바타는 한 번, 시각은 마지막 말에만', (tester) async {
    final server = _Server()
      ..items = '['
          '${_msg(1, "보리", 8, "첫 말", "2026-09-14T00:05:01Z")},'
          '${_msg(2, "보리", 8, "둘째 말", "2026-09-14T00:05:20Z")},'
          '${_msg(3, "보리", 8, "셋째 말", "2026-09-14T00:05:59Z")}'
          ']';

    await _pump(tester, server);

    expect(find.text('보리'), findsOneWidget, reason: '묶음의 첫 말에만 이름');
    expect(find.text('첫 말'), findsOneWidget);
    expect(find.text('셋째 말'), findsOneWidget);
    // 09:05 (기기 시간대가 어디든 세 말은 같은 분이라 시각은 하나)
    expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget, reason: '시각은 묶음의 마지막 말에만');
  });

  testWidgets('사람이 바뀌면 새 묶음 — 이름이 둘, 시각도 둘', (tester) async {
    final server = _Server()
      ..items = '['
          '${_msg(1, "보리", 8, "안녕", "2026-09-14T00:05:01Z")},'
          '${_msg(2, "콩이", 9, "응 안녕", "2026-09-14T00:05:20Z")}'
          ']';

    await _pump(tester, server);

    expect(find.text('보리'), findsOneWidget);
    expect(find.text('콩이'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsNWidgets(2));
  });

  testWidgets('날이 바뀌면 그 위에 날짜 구분선 — 같은 날 안에는 하나뿐', (tester) async {
    final server = _Server()
      ..items = '['
          '${_msg(1, "보리", 8, "어제 말", "2026-09-13T03:00:00Z")},'
          '${_msg(2, "보리", 8, "어제 또", "2026-09-13T03:10:00Z")},'
          '${_msg(3, "보리", 8, "오늘 말", "2026-09-14T03:00:00Z")}'
          ']';

    await _pump(tester, server);

    expect(find.byKey(const Key('chat-day-chip')), findsNWidgets(2), reason: '13일 · 14일 하나씩');
    expect(find.textContaining('9월 13일'), findsOneWidget);
    expect(find.textContaining('9월 14일'), findsOneWidget);
    expect(find.textContaining('요일'), findsNWidgets(2));
  });

  group('새 메시지 알약', () {
    String many(int n) => '[${[for (var i = 1; i <= n; i++) _msg(i, "보리", 8, "말 $i", "2026-09-14T00:${(i ~/ 2).toString().padLeft(2, "0")}:00Z")].join(",")}]';

    testWidgets('위로 올려 읽는 중에 남의 말이 오면 끌어내리지 않고 "새 메시지 N개" 알약 — 누르면 바닥으로', (tester) async {
      final server = _Server()..items = many(40);
      await _pump(tester, server, size: const Size(600, 900));
      expect(find.byKey(const Key('chat-new-messages')), findsNothing);

      // 위로 올린다(손가락을 아래로 끌면 옛 말이 보인다).
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.text('말 40'), findsNothing, reason: '바닥이 화면 밖으로 나갔다');

      server.items = '[${_msg(41, "콩이", 9, "새로 온 말", "2026-09-14T00:30:00Z")},${_msg(42, "콩이", 9, "하나 더", "2026-09-14T00:30:10Z")}]';
      await _nextPoll(tester);

      expect(find.text('새로 온 말'), findsNothing, reason: '읽던 자리를 지킨다 — 끌어내리지 않는다');
      expect(find.byKey(const Key('chat-new-messages')), findsOneWidget);
      expect(find.text('새 메시지 2개'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-new-messages')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-new-messages')), findsNothing);
      expect(find.text('하나 더'), findsOneWidget, reason: '바닥으로 내려왔다');
    });

    testWidgets('위에 긴 말이 여럿이고 아래는 짧은 말 — 알약을 누르면 빈 자리 위가 아니라 진짜 바닥에 선다', (tester) async {
      // 지연 생성 목록은 안 만든 줄의 높이를 어림한다. 위쪽(긴 말)만 만든 채로 바닥을 향하면
      // 어림이 실제보다 커서 실제 끝을 지나 빈 자리 위에 멈춘다 — 에뮬레이터에서 본 것(사진 셋 뒤 글 여섯).
      final long = List.filled(14, '긴 말입니다').join(' ');
      final items = [
        for (var i = 1; i <= 12; i++) _msg(i, "보리", 8, "$long $i", "2026-09-14T00:${i.toString().padLeft(2, "0")}:00Z"),
        for (var i = 13; i <= 40; i++) _msg(i, "보리", 8, "짧 $i", "2026-09-14T01:${(i - 13).toString().padLeft(2, "0")}:00Z"),
      ];
      final server = _Server()..items = '[${items.join(",")}]';
      await _pump(tester, server, size: const Size(600, 900));
      await tester.drag(find.byType(ListView), const Offset(0, 6000));
      await tester.pumpAndSettle();
      server.items = '[${_msg(41, "콩이", 9, "새로 온 말", "2026-09-14T02:00:00Z")}]';
      await _nextPoll(tester);
      expect(find.byKey(const Key('chat-new-messages')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-new-messages')));
      await tester.pumpAndSettle();

      final pos = tester.widget<ListView>(find.byType(ListView)).controller!.position;
      expect(pos.pixels, lessThanOrEqualTo(pos.maxScrollExtent + 0.5), reason: '실제 끝을 지나 빈 자리 위에 서 있다');
      expect(pos.maxScrollExtent - pos.pixels, lessThan(2), reason: '바닥까지 못 갔다');
      final listBottom = tester.getBottomLeft(find.byType(ListView)).dy;
      final lastBottom = tester.getBottomLeft(find.text('새로 온 말')).dy;
      expect(listBottom - lastBottom, lessThan(80), reason: '마지막 말이 화면 아래 가까이 있어야 한다 — 위에 떠 있으면 아래가 비어 있다');
    });

    testWidgets('바닥에 있으면 알약 없이 따라 내려간다', (tester) async {
      final server = _Server()..items = many(40);
      await _pump(tester, server, size: const Size(600, 900));

      server.items = '[${_msg(41, "콩이", 9, "새로 온 말", "2026-09-14T00:30:00Z")}]';
      await _nextPoll(tester);

      expect(find.byKey(const Key('chat-new-messages')), findsNothing);
      expect(find.text('새로 온 말'), findsOneWidget);
    });

    testWidgets('알약을 안 누르고 직접 바닥까지 내려도 사라진다', (tester) async {
      final server = _Server()..items = many(40);
      await _pump(tester, server, size: const Size(600, 900));
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      server.items = '[${_msg(41, "콩이", 9, "새로 온 말", "2026-09-14T00:30:00Z")}]';
      await _nextPoll(tester);
      expect(find.byKey(const Key('chat-new-messages')), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-new-messages')), findsNothing);

      // 바닥에 닿았으면 본 것이다 — 다시 올라가도 옛 개수가 되살아나면 안 된다.
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat-new-messages')), findsNothing,
          reason: '새로 온 말이 없는데 알약이 다시 뜨면 바닥에서 개수를 안 지운 것이다');
    });
  });
}

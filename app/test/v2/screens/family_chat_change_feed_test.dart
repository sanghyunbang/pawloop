// 남이 지운 말이 폴링에 따라온다 (ADR-0023, #500) — 같은 자리가 바뀌고, 대화 맨 아래로 올라오지 않는다.
//
// 그리고 **폴링이 언제 도는가** (#672) — 아래 '폴링 간격' 그룹. 조용하던 방에서 말을 걸면
// 걸려 있던 30초 타이머가 끝까지 흐르던 것을 여기서 잰다. 그러려면 12·24·30초 구간을 실제로
// 지나가야 하므로 **초를 세어** 민다 (`_advance`).
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

String _msg(int seq, String body, {String? deletedAt}) =>
    '{"id":$seq,"roomId":4,"roomSeq":$seq,"senderUserId":8,"senderName":"보통 사람","contentType":"text",'
    '"body":"$body","createdAt":"2026-09-15T07:0$seq:00Z","hiddenByBlock":false'
    '${deletedAt == null ? '' : ',"deletedAt":"$deletedAt"'}}';

/// 첫 장에는 말 둘, 그다음 폴링부터는 첫 말이 지워졌다고 알려 준다.
class _Server {
  final List<Uri> polls = [];
  bool deletedYet = false;

  /// 보낸 말 — 전송(POST /messages)이 몇 번 왔나 (#672).
  int sends = 0;

  /// 올린 사진 — 사진 연타를 재는 데 쓴다 (#672).
  int uploads = 0;

  /// **몇 번째 폴링이 끊기는가** (1부터 센다). 망이 흔들리는 것을 흉내 낸다 (#672).
  final Set<int> failPolls = {};

  /// 사진 올리기에 걸리는 시간. 0이면 즉시다 — 사진 연타 테스트만 이걸 켠다 (#672).
  Duration uploadTakes = Duration.zero;

  late final AuthedClient client = AuthedClient(
    inner: MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      if (request is http.MultipartRequest) {
        uploads++;
        if (uploadTakes > Duration.zero) {
          await Future<void>.delayed(uploadTakes);
        }
        return _json(
            '[{"id":31,"key":"chats/4/a.jpg","url":"https://cdn/chats/a.jpg",'
            '"category":"CHAT_IMAGE","status":"ready"}]',
            200);
      }
      if (request.url.path.endsWith('/read')) return _json('{}', 200);
      if (request.method == 'POST' && request.url.path.endsWith('/messages')) {
        sends++;
        return _json(_msg(3, '자니'), 201);
      }
      polls.add(request.url);
      if (failPolls.contains(polls.length)) {
        // 요청이 끊긴다 — ChatRepository 가 ChatFailure 로 바꿔 화면에 준다.
        throw Exception('connection reset');
      }
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

Future<void> _pump(WidgetTester tester, _Server server, {FakeMediaPicker? picker}) async {
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

/// 다음 폴링이 돌 때까지 — 정책의 첫 간격은 몇 초라 넉넉히 민다.
Future<void> _nextPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

/// **딱 [step] 만큼만** 민다 (#672).
///
/// [WidgetTester.pumpAndSettle] 을 쓰면 안 된다 — 프레임이 멈출 때까지 알아서 시간을 밀어서,
/// "지금 몇 초짜리 타이머가 걸려 있나" 를 재는 자리에서는 눈금 없는 자로 재는 것과 같다.
/// 백오프 구간(12 · 24 · 30초)은 초를 세어야만 지나갈 수 있다.
///
/// 민 다음에는 **시간을 더 밀지 않고** 프레임만 몇 장 돌린다 — 응답(Future)이 돌아와
/// `setState` 가 반영될 자리다.
Future<void> _advance(WidgetTester tester, Duration step) async {
  await tester.pump(step);
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration.zero);
  }
}

/// 45초를 조용히 흘려보낸다 — 정책의 3 → 6 → 12 → 24 를 **초로 세어** 지난다 (#672).
///
/// 이 넷을 지나면 빈손 카운터가 4라 다음 간격이 상한 30초다. 돌아올 때 폴링은 다섯 번
/// (첫 장 + 빈손 넷) 돌아 있고, 여섯 번째는 30초 뒤로 걸려 있다.
Future<void> _fallSilentFor45s(WidgetTester tester, _Server server) async {
  for (final seconds in const [3, 6, 12, 24]) {
    await _advance(tester, Duration(seconds: seconds));
  }
  expect(server.polls, hasLength(5),
      reason: '3 · 6 · 12 · 24초에 한 번씩 — 초가 안 맞으면 여기까지 못 온다');
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

  group('폴링 간격 — 초를 세어 잰다 (#672)', () {
    testWidgets('45초 침묵으로 30초까지 내려앉아도, 말을 걸면 다음 폴링이 3초 뒤에 돈다', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      expect(server.polls, hasLength(1), reason: '첫 장');

      await _fallSilentFor45s(tester, server);

      // 20초를 더 밀어도 안 돈다 — 30초 타이머가 걸려 있다. 이게 지금 사람이 겪는 것이다.
      await _advance(tester, const Duration(seconds: 20));
      expect(server.polls, hasLength(5), reason: '상한 30초에 걸려 있다');

      // 말을 건다. 이것이 "대화가 재개됐다" 는 가장 확실한 신호다.
      await tester.enterText(find.byType(TextField), '자니');
      await tester.tap(find.byKey(const Key('chat-send')));
      await _advance(tester, Duration.zero);
      expect(server.sends, 1, reason: '보내긴 보냈다');
      expect(server.polls, hasLength(5), reason: '전송 자체는 폴링이 아니다');

      await _advance(tester, const Duration(seconds: 4));

      expect(server.polls, hasLength(6), reason: '''
전송이 카운터만 되돌리고 타이머를 그냥 두면, 남아 있는 30초가 끝까지 흐른다(앞에서 20초를
흘렸으니 10초 더). 그동안 상대의 답장은 화면에 안 뜬다 — 양쪽이 이러면 왕복이 1분이다.

_deliver 의 _wakePolling() 을 빼면 여기가 빨간불이다.''');
    });

    testWidgets('빈손과 실패가 번갈아 들어와도 넷을 더해 30초로 내려앉지 않는다', (tester) async {
      // 3번째 · 5번째 폴링이 끊긴다 — 지하철에서 망이 흔들리는 모양이다.
      final server = _Server()..failPolls.addAll({3, 5});
      await _pump(tester, server);

      await _advance(tester, const Duration(seconds: 3)); // 2번째 — 빈손 1
      expect(server.polls, hasLength(2));

      await _advance(tester, const Duration(seconds: 6)); // 3번째 — 실패 1
      expect(server.polls, hasLength(3), reason: '빈손 1이라 6초 뒤다');

      await _advance(tester, const Duration(seconds: 6)); // 4번째 — 빈손 2
      expect(server.polls, hasLength(4), reason: '''
실패는 빈손이 아니다. 한 카운터에 같이 넣으면 여기서 2회분(12초)을 기다리므로 6초에는
아직 안 돈다 — 이 단언이 두 카운터를 합치는 것을 막는다.''');

      await _advance(tester, const Duration(seconds: 12)); // 5번째 — 실패 2
      expect(server.polls, hasLength(5), reason: '빈손 2이라 12초 뒤다');

      await _advance(tester, const Duration(seconds: 13));

      expect(server.polls, hasLength(6), reason: '''
빈손 둘 · 실패 둘이다. 합쳐서 세면 넷이라 상한 30초로 내려앉지만, 둘은 다른 사실이라
각자 물러난 뒤 느린 쪽(12초)을 쓴다 — 망이 흔들려도 방의 리듬을 잃지 않는다.''');
    });

    testWidgets('사진을 여러 장 보내도 타이머가 장마다 다시 걸리지 않는다 — 깨우려던 것이 더 늦어지면 안 된다',
        (tester) async {
      // 한 장 올리는 데 1초 걸린다고 해 두면, 타이머를 장마다 다시 거는지 초로 드러난다.
      final server = _Server()..uploadTakes = const Duration(seconds: 1);
      final picker = FakeMediaPicker((_) => [
            PickedImage(name: 'a.jpg', bytes: Uint8List.fromList([1])),
            PickedImage(name: 'b.jpg', bytes: Uint8List.fromList([2])),
            PickedImage(name: 'c.jpg', bytes: Uint8List.fromList([3])),
          ]);

      await _pump(tester, server, picker: picker);
      await _fallSilentFor45s(tester, server);

      await tester.tap(find.byKey(const Key('chat-photo')));
      // 한 장에 1초 — 첫 장은 +1초, 마지막 장은 +3초에 끝난다.
      for (var i = 0; i < 3; i++) {
        await _advance(tester, const Duration(seconds: 1));
      }
      expect(server.uploads, 3);
      expect(server.sends, 3, reason: '사진 하나에 메시지 하나');

      // 첫 장이 끝난 +1초에 3초 타이머가 걸렸다면 +4초에 돈다. 장마다 다시 걸었다면 +6초다.
      await _advance(tester, const Duration(milliseconds: 1500));

      expect(server.polls, hasLength(6), reason: '''
장마다 타이머를 새로 걸면 마지막 장이 끝날 때까지 계속 뒤로 밀린다 — 열 장이면 깨우려던
폴링이 오히려 더 늦어진다. 이미 더 짧게 걸려 있으면 다시 안 건다.''');
    });
  });
}

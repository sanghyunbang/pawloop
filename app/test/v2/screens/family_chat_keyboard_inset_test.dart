// 채팅 입력창과 키보드 사이 (#671) — 키보드가 올라오면 입력창이 그 바로 위에 붙어야 한다.
//
// 재는 것은 "인셋이 붙었는가" 가 아니라 **값**이다. 보내기 단추(`chat-send`)의 아래 y 와
// 키보드 윗변 사이가 몇 px 인가. 두 번 밀리던 시절에는 이 사이가 300 을 넘었다.
//
// 키보드는 반드시 `tester.view.viewInsets` 로 **엔진과 같은 길**로 올린다. `MediaQuery` 위젯으로
// 감싸면 Scaffold 가 몸체용 MediaQuery 에서 아래 인셋을 지우는 그 단계를 안 거치게 되어,
// 두 번 미는 코드에서도 초록이 나오는 가짜 테스트가 된다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/data/post_media_repository.dart';
import 'package:heat_trip_flutter/v2/screens/family_chat_screen.dart';

import '../support/fake_media_picker.dart';

const String _base = 'https://api.test';

/// 화면 800x1600 · 홈 인디케이터 34 · 키보드 300 — 이슈 #671 이 실기기에서 잰 것과 같은 판이다.
const double _screenHeight = 1600;
const double _homeIndicator = 34;
const double _keyboard = 300;

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

/// 말 한 마디만 있는 방. 이 테스트가 보는 것은 목록이 아니라 입력창의 자리다.
AuthedClient _client() => AuthedClient(
      inner: MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/read')) return _json('{}', 200);
        return _json(
            '{"items":[{"id":1,"roomId":4,"roomSeq":1,"senderUserId":8,"senderName":"보통 사람",'
            '"contentType":"text","body":"안녕하세요","createdAt":"2026-09-14T07:00:00Z",'
            '"hiddenByBlock":false}],"lastSeq":1,"hasMore":false}',
            200);
      }),
      baseUrl: _base,
      store: _FakeTokenStore(),
    );

Future<void> _pump(WidgetTester tester, {required bool keyboardUp}) async {
  tester.view.physicalSize = const Size(800, _screenHeight);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(bottom: _homeIndicator);
  tester.view.viewPadding = const FakeViewPadding(bottom: _homeIndicator);
  // 엔진이 키보드를 알리는 길 그대로. Scaffold 는 이 값을 보고 몸체를 밀어 올리고,
  // 몸체용 MediaQuery 에서는 이 값을 지운다. 그 지우기를 거쳐야 진짜 테스트가 된다.
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardUp ? _keyboard : 0);
  addTearDown(tester.view.reset);

  final client = _client();
  await tester.pumpWidget(MaterialApp(
    home: FamilyChatScreen(
      roomId: 4,
      repository: ChatRepository(baseUrl: _base, client: client),
      media: PostMediaRepository(baseUrl: _base, client: client),
      picker: FakeMediaPicker((_) => const []),
    ),
  ));
  await tester.pumpAndSettle();
}

double _sendBottom(WidgetTester tester) => tester.getRect(find.byKey(const Key('chat-send'))).bottom;

void main() {
  tearDown(AuthState.resetForTest);

  testWidgets('키보드를 올리면 보내기 단추가 키보드 바로 위에 붙는다 — 두 번 밀리지 않는다', (tester) async {
    await _pump(tester, keyboardUp: true);

    const keyboardTop = _screenHeight - _keyboard; // 1300
    final gap = keyboardTop - _sendBottom(tester);

    // 두 번 밀리면 이 사이가 키보드 높이(300)만큼 더 벌어진다. 붙어 있다고 부를 수 있는 건
    // 입력창 자체의 아래 여백 정도(14) 안쪽이다.
    expect(gap, greaterThanOrEqualTo(0),
        reason: '보내기 단추가 키보드에 가리면 안 된다 (사이 $gap)');
    expect(gap, lessThan(40),
        reason: '키보드 위로 떠오르면 안 된다 — 두 번 밀린 것이다 (사이 $gap)');
  });

  testWidgets('키보드를 내리면 보내기 단추가 홈 인디케이터를 안 침범한다', (tester) async {
    await _pump(tester, keyboardUp: false);

    const safeBottom = _screenHeight - _homeIndicator; // 1566
    expect(_sendBottom(tester), lessThanOrEqualTo(safeBottom),
        reason: '키보드가 없을 때는 아래 안전영역을 비워 둔다 '
            '(단추 아래 ${_sendBottom(tester)} · 안전선 $safeBottom)');
  });
}

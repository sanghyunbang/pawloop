import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 앱이 읽는 키가 서버가 주는 키와 같은가. (이슈 #82 에서 찾은 것)
///
/// ## 왜 이 파일이 따로 있는가
///
/// 메시지 목록의 키가 한동안 **`messages`** 였다. 서버는 `items` 를 준다
/// (`ChatMessagePageResponse` · 계약의 `ChatMessagePage`). 그래서 실기기에서 대화가
/// **언제나 비어 보였다.**
///
/// 그런데 테스트는 초록불이었다 — `MockClient` 가 `messages` 로 응답을 흉내 냈기 때문이다.
/// **서버를 잘못 흉내 낸 테스트는 아무것도 지키지 못한다.** 같은 방식으로 charset 을
/// 빠뜨려 한글이 깨진 적도 있다(#81).
///
/// 그래서 여기서는 응답에 **계약의 키만** 넣는다. 앱이 다른 키를 읽으면 값을 못 찾아
/// 빨간불이 된다.
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

ChatRepository _repo(MockClient inner) => ChatRepository(
      baseUrl: _base,
      client: AuthedClient(inner: inner, baseUrl: _base, store: _FakeTokenStore()),
    );

http.Response _json(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('메시지 목록의 키는 items 다 — messages 를 읽던 시절에는 언제나 비었다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '{"items":[{"id":1,"roomSeq":1,"senderUserId":2,'
          '"senderName":"보리아빠","body":"안녕하세요"}],'
          '"lastSeq":1,"hasMore":false}',
          200,
        )));

    final page = await repo.messages(7);

    expect(
      page.messages,
      hasLength(1),
      reason: '서버는 items 를 준다. messages 를 읽으면 목록이 언제나 비어 있다',
    );
    expect(page.messages.single.body, '안녕하세요');
  });

  test('방 목록이 myRole 을 읽는다 — 강퇴 버튼을 띄울 유일한 근거다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"id":1,"title":"우리 가족","tag":"가족","lastSeq":0,'
          '"lastReadSeq":0,"unread":0,"memberCount":2,"myRole":"OWNER"}]',
          200,
        )));

    expect((await repo.rooms()).single.isOwner, isTrue);
  });

  test('myRole 이 없거나 MEMBER 면 방장이 아니다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '[{"id":1,"title":"a","tag":"b","lastSeq":0,"lastReadSeq":0,'
          '"unread":0,"memberCount":2},'
          '{"id":2,"title":"c","tag":"d","lastSeq":0,"lastReadSeq":0,'
          '"unread":0,"memberCount":2,"myRole":"MEMBER"}]',
          200,
        )));

    expect(
      (await repo.rooms()).map((r) => r.isOwner),
      [false, false],
      reason: '모르는 값이 와도 방장으로 보면 안 된다 — 못 하는 버튼을 띄우게 된다',
    );
  });

  test('한글이 깨지지 않는다 — charset 을 빠뜨린 응답을 흉내 내면 여기가 먼저 걸린다', () async {
    final repo = _repo(MockClient((req) async => _json(
          '{"items":[{"id":1,"roomSeq":1,"senderUserId":2,'
          '"senderName":"엄마","body":"보리 저녁밥 줬어요"}],'
          '"lastSeq":1,"hasMore":false}',
          200,
        )));

    final page = await repo.messages(7);

    expect(page.messages.single.senderName, '엄마');
    expect(page.messages.single.body, '보리 저녁밥 줬어요');
  });
}

// 말풍선 사진 — 이슈 #452. 보낼 때는 mediaId 와 image 가 실리고, 받을 때는 media 를 읽는다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';

class _NoTokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'token';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

const _photoMessage = '{"id":5,"roomId":4,"roomSeq":3,"senderUserId":19,"senderName":"보리아빠",'
    '"contentType":"image","body":"","createdAt":"2026-09-14T07:00:00Z","hiddenByBlock":false,'
    '"media":{"id":17,"kind":"image","url":"https://cdn/chats/a.jpg","posterUrl":null,"width":480,"height":600}}';

ChatRepository _repo(http.Response Function(http.Request) handler, List<http.Request> seen) => ChatRepository(
      baseUrl: 'https://api.example.test',
      client: AuthedClient(
        inner: MockClient((request) async {
          seen.add(request);
          return handler(request);
        }),
        baseUrl: 'https://api.example.test',
        store: _NoTokens(),
      ),
    );

http.Response _json(String body, [int status = 200]) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

void main() {
  test('mediaId 가 있으면 본문에 mediaId 와 contentType=image 가 실리고, 응답의 media 를 읽는다', () async {
    final seen = <http.Request>[];
    final repo = _repo((_) => _json(_photoMessage, 201), seen);

    final sent = await repo.send(4, '', 'key-1', mediaId: 17);

    final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(body['mediaId'], 17);
    expect(body['contentType'], 'image');
    expect(body['body'], '');
    expect(sent.isImage, isTrue);
    expect(sent.media?.id, 17);
    expect(sent.media?.url, 'https://cdn/chats/a.jpg');
    expect(sent.media?.aspectRatio, closeTo(0.8, 0.001), reason: '480×600 = 4:5');
  });

  test('글자 메시지는 예전 그대로 — mediaId 키가 없고 contentType 은 text, media 는 null', () async {
    final seen = <http.Request>[];
    final repo = _repo(
        (_) => _json('{"id":6,"roomId":4,"roomSeq":4,"senderUserId":19,"senderName":"보리아빠",'
            '"contentType":"text","body":"글자","createdAt":"2026-09-14T07:00:00Z","hiddenByBlock":false}', 201),
        seen);

    final sent = await repo.send(4, '글자', 'key-2');

    final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
    expect(body.containsKey('mediaId'), isFalse);
    expect(body['contentType'], 'text');
    expect(sent.isImage, isFalse);
    expect(sent.media, isNull);
  });

  test('목록의 사진 메시지는 media 가 붙고, 지워진 사진 메시지는 media 가 null 이라도 자리는 남는다', () async {
    final repo = _repo(
        (_) => _json('{"items":[$_photoMessage,'
            '{"id":7,"roomId":4,"roomSeq":4,"senderUserId":19,"senderName":"보리아빠","contentType":"image",'
            '"body":"","createdAt":"2026-09-14T07:01:00Z","deletedAt":"2026-09-14T07:02:00Z","hiddenByBlock":false,"media":null}'
            '],"lastSeq":4,"hasMore":false}'),
        []);

    final page = await repo.messages(4);

    expect(page.messages.map((m) => m.roomSeq), [3, 4]);
    expect(page.messages.first.media?.id, 17);
    expect(page.messages.last.isImage, isTrue);
    expect(page.messages.last.deleted, isTrue);
    expect(page.messages.last.media, isNull);
  });

  test('방 목록의 lastMessage 가 사진이면 그렇다고 말한다 — 캡션이 없어도 "사진" 으로 그릴 근거', () async {
    final repo = _repo(
        (_) => _json('[{"id":4,"title":"크루","tag":"크루","lastSeq":3,"lastReadSeq":1,"unread":2,"memberCount":2,'
            '"myRole":"MEMBER","muted":false,"lastMessage":$_photoMessage}]'),
        []);

    final rooms = await repo.rooms();

    expect(rooms.single.lastMessageIsImage, isTrue);
    expect(rooms.single.lastMessageBody, '');
  });
}

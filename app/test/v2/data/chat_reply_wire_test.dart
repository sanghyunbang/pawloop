// 답장(#452)의 전선 — 보낼 때는 `replyToId` 하나, 받을 때는 `replyTo` 미리보기. 대기 항목은 인용을 잃지 않는다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/chat_outbox.dart';
import 'package:heat_trip_flutter/v2/data/chat_repository.dart';
import 'package:heat_trip_flutter/v2/domain/chat_reply.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

const _sent = '{"id":9,"roomId":4,"roomSeq":3,"senderUserId":1,"senderName":"나","contentType":"text",'
    '"body":"좋아요","createdAt":"2026-09-14T07:05:00Z","hiddenByBlock":false,'
    '"replyTo":{"id":1,"senderName":"보리엄마","preview":"저녁 산책 갈까요?","deleted":false}}';

void main() {
  group('ChatRepository.send', () {
    late List<Map<String, dynamic>> bodies;
    late ChatRepository repo;

    setUp(() {
      bodies = [];
      final client = AuthedClient(
        inner: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(_sent, 201, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
        baseUrl: _base,
        store: _FakeTokenStore(),
      );
      repo = ChatRepository(baseUrl: _base, client: client);
    });

    test('replyToId 를 주면 본문에 실린다 — 원문의 내용은 보내지 않는다', () async {
      await repo.send(4, '좋아요', 'KEY-1', replyToId: 1);

      expect(bodies.single['replyToId'], 1);
      expect(bodies.single.keys, isNot(contains('replyTo')));
    });

    test('답장이 아니면 replyToId 키 자체가 없다', () async {
      await repo.send(4, '그냥 말', 'KEY-2');

      expect(bodies.single.containsKey('replyToId'), isFalse);
    });

    test('응답의 replyTo 를 읽는다', () async {
      final sent = await repo.send(4, '좋아요', 'KEY-3', replyToId: 1);

      expect(sent.replyTo, const ChatReplyTo(id: 1, senderName: '보리엄마', preview: '저녁 산책 갈까요?'));
    });
  });

  group('ChatMessageItem.tryParse', () {
    test('replyTo 가 없거나 null 이면 null', () {
      final json = jsonDecode('{"id":1,"roomSeq":1,"senderUserId":8,"senderName":"a","body":"b","replyTo":null}')
          as Map<String, dynamic>;

      expect(ChatMessageItem.tryParse(json)!.replyTo, isNull);
    });

    test('지워진 원문의 미리보기를 읽는다', () {
      final json = jsonDecode('{"id":2,"roomSeq":2,"senderUserId":8,"senderName":"a","body":"답",'
          '"replyTo":{"id":1,"senderName":"보리엄마","preview":"삭제된 메시지","deleted":true}}') as Map<String, dynamic>;

      final reply = ChatMessageItem.tryParse(json)!.replyTo!;

      expect(reply.deleted, isTrue);
      expect(reply.preview, '삭제된 메시지');
    });
  });

  group('PendingMessage', () {
    const quote = ChatReplyTo(id: 1, senderName: '보리엄마', preview: '저녁 산책 갈까요?');

    test('답장으로 만든 대기 항목은 실패 · 재전송을 지나도 인용을 든다 — 키도 그대로', () {
      final first = PendingMessage.create('좋아요', replyTo: quote);

      final retried = first.failed().retrying();

      expect(retried.replyTo, quote);
      expect(retried.clientMsgId, first.clientMsgId);
    });

    test('사진 답장은 올린 뒤에도 인용을 든다', () {
      final photo = PendingPhoto(bytes: Uint8List.fromList([1, 2, 3]), width: 4, height: 5);
      final pending = PendingMessage.photo(photo, replyTo: quote);

      expect(pending.uploaded(31).replyTo, quote);
      expect(pending.uploaded(31).mediaId, 31);
    });

    test('답장이 아니면 인용이 없다', () {
      expect(PendingMessage.create('그냥 말').replyTo, isNull);
    });
  });
}

// 답장 미리보기 규칙 (#452) — 서버(`ChatMessageResponse.ReplyTo.of`)와 같아야 확정되는 순간 글자가 안 바뀐다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/chat_reply.dart';

void main() {
  group('replyPreviewOf', () {
    test('공백·줄바꿈은 한 칸으로 접고 앞뒤를 자른다', () {
      expect(replyPreviewOf('  저녁 산책\n\n갈까요?  ', isImage: false, deleted: false), '저녁 산책 갈까요?');
    });

    test('지워진 원문은 "삭제된 메시지" — 본문이 있어도', () {
      expect(replyPreviewOf('지운 말', isImage: false, deleted: true), '삭제된 메시지');
    });

    test('캡션 없는 사진은 "사진", 캡션이 있으면 캡션', () {
      expect(replyPreviewOf('', isImage: true, deleted: false), '사진');
      expect(replyPreviewOf('공원이에요', isImage: true, deleted: false), '공원이에요');
    });

    test('80자를 넘으면 거기서 자르고 … — 이모지도 한 자다', () {
      final long = '🐶' * 100;

      final preview = replyPreviewOf(long, isImage: false, deleted: false);

      expect(preview.runes.length, 81);
      expect(preview.endsWith('…'), isTrue);
      expect(preview.contains('�'), isFalse, reason: '보조평면 문자를 반으로 자르면 깨진 글자가 남는다');
    });

    test('80자면 그대로다', () {
      final exact = '가' * 80;
      expect(replyPreviewOf(exact, isImage: false, deleted: false), exact);
    });
  });

  group('ChatReplyTo.tryParse', () {
    test('서버 모양을 읽는다', () {
      final parsed = ChatReplyTo.tryParse({'id': 7, 'senderName': '보리엄마', 'preview': '저녁 산책', 'deleted': false});

      expect(parsed, const ChatReplyTo(id: 7, senderName: '보리엄마', preview: '저녁 산책'));
    });

    test('null 이나 id 없는 것은 null — 답장이 아닌 메시지는 replyTo: null 로 온다', () {
      expect(ChatReplyTo.tryParse(null), isNull);
      expect(ChatReplyTo.tryParse({'senderName': '?'}), isNull);
      expect(ChatReplyTo.tryParse('x'), isNull);
    });

    test('deleted 를 읽는다', () {
      expect(ChatReplyTo.tryParse({'id': 1, 'senderName': 'a', 'preview': '삭제된 메시지', 'deleted': true})!.deleted, isTrue);
    });
  });
}

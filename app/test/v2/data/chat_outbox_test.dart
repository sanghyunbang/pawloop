import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/chat_outbox.dart';

/// 낙관적 전송의 멱등키. (이슈 #81 완료 조건 7)
///
/// 여기가 지키는 것은 **재전송이 키를 새로 만들지 않는다**는 것이다. 새로 만들도록 되돌리면
/// `재전송은 같은 멱등키를 다시 쓴다` 가 빨간불이어야 한다.
void main() {
  group('멱등키', () {
    test('부를 때마다 다르다', () {
      final keys = {for (var i = 0; i < 200; i++) newClientMsgId()};

      expect(keys.length, 200, reason: '충돌이 있으면 서로 다른 메시지가 하나로 합쳐진다');
    });

    test('서버 컬럼(64자)에 들어가고 URL 에 실어도 안전한 문자만 쓴다', () {
      for (var i = 0; i < 50; i++) {
        final key = newClientMsgId();

        expect(key.length, lessThanOrEqualTo(64));
        expect(
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key),
          isTrue,
          reason: 'base64url 이어야 한다. 패딩(=)이 남아 있으면 URL 에서 인코딩이 필요해진다: $key',
        );
      }
    });

    test('16바이트를 담는다 — 22자가 나온다', () {
      expect(newClientMsgId().length, 22);
    });
  });

  group('재전송 — 이 그룹이 완료 조건 7이다', () {
    test('재전송은 같은 멱등키를 다시 쓴다', () {
      final first = PendingMessage.create('보리 밥 줬어요');
      final afterFailure = first.failed();
      final retried = afterFailure.retrying();

      expect(
        retried.clientMsgId,
        first.clientMsgId,
        reason: '''
키를 새로 만들면 멱등이 무의미해진다.

첫 전송이 서버에 닿았는데 응답만 못 받은 경우(타임아웃·비행기 모드), 새 키로 재전송하면
서버에 같은 말이 두 번 남는다. 서버의 (room_id, sender_user_id, client_msg_id) UNIQUE 는
키가 다르면 그냥 통과시킨다.

완료 조건 3 이 "재전송하면 서버에 메시지가 1개만 생긴다" 인 것이 이것이다.''',
      );
    });

    test('여러 번 실패하고 여러 번 재전송해도 키가 그대로다', () {
      var message = PendingMessage.create('사료 사올게');
      final original = message.clientMsgId;

      for (var attempt = 0; attempt < 5; attempt++) {
        message = message.failed().retrying();
        expect(message.clientMsgId, original, reason: '$attempt 번째 재전송에서 키가 바뀌었다');
      }
    });

    test('본문도 그대로다 — 사용자가 쓴 글이 바뀌면 안 된다', () {
      final first = PendingMessage.create('저녁 산책 제가 갈게요');
      final retried = first.failed().retrying();

      expect(retried.body, first.body);
    });

    test('만든 시각이 그대로다 — 재전송이 목록 순서를 흔들면 안 된다', () {
      final first = PendingMessage.create('보리 물 갈았어');
      final retried = first.failed().retrying();

      expect(retried.createdAt, first.createdAt);
    });

    test('서로 다른 메시지는 서로 다른 키다', () {
      final one = PendingMessage.create('첫 번째');
      final two = PendingMessage.create('두 번째');

      expect(one.clientMsgId, isNot(two.clientMsgId));
    });
  });

  group('상태', () {
    test('새로 만들면 보내는 중이다', () {
      expect(PendingMessage.create('안녕').state, PendingState.sending);
    });

    test('실패하면 failed 다 — 목록에서 지우지 않는다', () {
      expect(PendingMessage.create('안녕').failed().state, PendingState.failed);
    });

    test('재전송하면 다시 보내는 중이다', () {
      expect(
        PendingMessage.create('안녕').failed().retrying().state,
        PendingState.sending,
      );
    });
  });
}

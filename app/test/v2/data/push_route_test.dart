// 서버 푸시의 data → 우리 payload (#83) — 순수 함수라 firebase 없이 잰다.
//
// 푸시라고 다른 길을 내지 않는다는 것이 요점이다: 일정 배정 푸시의 payload 는 기기의 일정 알림과
// **같은 모양**이어야 누르면 그 날의 그 줄까지 간다(#420 후속).
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/notification_route.dart';
import 'package:heat_trip_flutter/v2/data/push_route.dart';

void main() {
  group('data → payload', () {
    test('일정 배정은 일정 알림과 같은 모양 — 누르면 그 날의 그 줄까지 간다', () {
      final payload = pushPayloadOf({
        'kind': 'schedule.assigned',
        'scheduleId': '41',
        'onDate': '2026-10-20',
      });

      expect(payload, 'schedule-reminder:41:2026-10-20');
      expect(destinationOf(payload), NotificationDestination.schedule);
      expect(scheduleFocusOf(payload),
          ScheduleFocus(scheduleId: 41, onDate: DateTime(2026, 10, 20)),
          reason: '탭까지만 가면 사용자는 알림이 말한 그 날을 다시 찾아야 한다');
    });

    test('채팅은 채팅 탭', () {
      final payload = pushPayloadOf({
        'kind': 'chat.message',
        'roomId': '7',
        'roomSeq': '12',
        'messageId': '99',
      });

      expect(payload, 'chat-message:7');
      expect(destinationOf(payload), NotificationDestination.chat);
      expect(tabOf(NotificationDestination.chat), 4);
    });

    test('숫자로 와도 읽는다 — 플랫폼에 따라 문자열이 아닐 수 있다', () {
      expect(pushPayloadOf({'kind': 'chat.message', 'roomId': 7}), 'chat-message:7');
    });

    test('모르는 종류·틀린 모양은 null — 앱만 열린다', () {
      expect(pushPayloadOf({}), isNull);
      expect(pushPayloadOf({'kind': 'walk.reminder'}), isNull,
          reason: '서버가 앱보다 먼저 바뀔 수 있다 — 모르는 것으로 죽으면 안 된다');
      expect(pushPayloadOf({'kind': 'schedule.assigned', 'scheduleId': '41'}), isNull,
          reason: '날짜 없이는 그 날을 못 연다 — 반쯤 맞는 payload 를 만들지 않는다');
      expect(pushPayloadOf({'kind': 'schedule.assigned', 'scheduleId': '마흔하나', 'onDate': '2026-10-20'}),
          isNull);
      expect(pushPayloadOf({'kind': 'schedule.assigned', 'scheduleId': '0', 'onDate': '2026-10-20'}), isNull,
          reason: '일정 id 는 1부터다');
      expect(pushPayloadOf({'kind': 'chat.message'}), isNull);
      expect(pushPayloadOf({'kind': 'chat.message', 'roomId': '-3'}), isNull);
    });
  });

  group('앞에 떠 있을 때 보여 줄 것', () {
    test('서버의 제목·본문을 그대로, payload 는 같은 규칙으로', () {
      final notice = foregroundNoticeOf(
        data: {'kind': 'chat.message', 'roomId': '7'},
        title: '엄마',
        body: '오늘 산책 갈래?',
      );

      expect(notice, isNotNull);
      expect(notice!.title, '엄마');
      expect(notice.body, '오늘 산책 갈래?');
      expect(notice.payload, 'chat-message:7',
          reason: '앞에서 띄운 것을 눌러도 뒤에서 온 것과 같은 곳으로 간다');
    });

    test('제목이 없으면 null — 띄울 것이 없다', () {
      expect(foregroundNoticeOf(data: {'kind': 'chat.message', 'roomId': '7'}, title: null, body: 'x'),
          isNull);
      expect(foregroundNoticeOf(data: {'kind': 'chat.message', 'roomId': '7'}, title: '  ', body: 'x'),
          isNull);
    });

    test('같은 방은 같은 번호라 겹치지 않고 바뀐다 · 다른 방·일정·기기 알림과는 다르다', () {
      int idOf(Map<String, Object?> data) => foregroundNoticeOf(data: data, title: 't', body: '')!.id;
      const room7 = {'kind': 'chat.message', 'roomId': '7'};
      const room8 = {'kind': 'chat.message', 'roomId': '8'};
      const schedule7 = {'kind': 'schedule.assigned', 'scheduleId': '7', 'onDate': '2026-10-20'};
      const schedule41 = {'kind': 'schedule.assigned', 'scheduleId': '41', 'onDate': '2026-10-20'};

      expect(idOf(room7), idOf(room7), reason: '한 방에서 다섯 통이 오면 알림은 마지막 한 장이다');
      expect(idOf(room7), isNot(idOf(room8)));
      expect(idOf(room7), isNot(idOf(schedule7)), reason: '방 7 과 일정 7 은 다른 알림이다');
      expect(idOf(schedule41), isNot(41),
          reason: '기기의 일정 알림이 일정 id 를 번호로 쓴다 — 같으면 예약된 그 알림을 덮는다');
      expect(idOf(room7), isNot(341), reason: '저녁 산책 알림의 번호');
      expect(idOf(room7), isNot(486), reason: '주간 정리 알림의 번호');
    });

    test('모르는 종류도 띄운다 — 누르면 앱만 열린다', () {
      final notice = foregroundNoticeOf(data: {'kind': 'something.new'}, title: '새 소식', body: '');

      expect(notice, isNotNull);
      expect(notice!.payload, isNull);
    });
  });
}

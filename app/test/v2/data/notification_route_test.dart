// 알림을 누르면 어디로 (#486 후속) — payload 읽기 · 탭 번호 · 한 번만 간다.
// 일정 알림은 그 위에 **그 일정**까지 싣는다(#420 후속) — id 와 그 날.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/notification_route.dart';
import 'package:heat_trip_flutter/v2/domain/schedule_reminder.dart';

final _anyDay = DateTime(2026, 10, 20);

void main() {
  setUp(NotificationRouteInbox.resetForTest);
  tearDown(NotificationRouteInbox.resetForTest);

  group('payload 읽기', () {
    test('세 알림이 각자의 자리로', () {
      expect(destinationOf(walkReminderPayload), NotificationDestination.home);
      expect(destinationOf(scheduleReminderPayload), NotificationDestination.schedule);
      expect(destinationOf(weeklyReportPayload), NotificationDestination.weeklyReport);
    });

    test('일정 알림은 id·날짜를 달고 와도 같은 곳이다 — 앞머리만 본다', () {
      expect(destinationOf(scheduleReminderPayloadFor(41, DateTime(2026, 10, 20))),
          NotificationDestination.schedule,
          reason: '통째로 비교하면 새 payload 가 모르는 값이 되어 앱만 열린다');
    });

    test('채팅 푸시(#83)는 채팅 탭 — 방 id 를 달고 와도 앞머리만 본다', () {
      expect(chatMessagePayloadFor(7), 'chat-message:7');
      expect(destinationOf(chatMessagePayloadFor(7)), NotificationDestination.chat);
      expect(tabOf(NotificationDestination.chat), 4, reason: '채팅은 다섯째 칸이다(#419 이후)');
    });

    test('payload 가 없거나 모르는 값이면 null — 앱만 열린다', () {
      expect(destinationOf(null), isNull);
      expect(destinationOf(''), isNull);
      expect(destinationOf('무언가-새로운-것'), isNull,
          reason: '알림은 며칠 뒤에 울린다 — 그 사이 앱이 바뀌어도 죽지 않아야 한다');
    });
  });

  group('그 일정까지 (#420 후속)', () {
    test('싣고 읽는다 — 같은 값이 돌아온다', () {
      final payload = scheduleReminderPayloadFor(41, DateTime(2026, 10, 20, 14, 30));

      expect(payload, 'schedule-reminder:41:2026-10-20', reason: '시각은 안 싣는다 — 여는 것은 하루다');
      expect(scheduleFocusOf(payload),
          ScheduleFocus(scheduleId: 41, onDate: DateTime(2026, 10, 20)));
    });

    test('옛 알림(앞머리만)은 그 일정이 없다 — 탭까지만 간다', () {
      expect(scheduleFocusOf(scheduleReminderPayload), isNull,
          reason: '이미 걸어 둔 알림은 며칠 뒤에 울린다 — 그것 때문에 죽으면 안 된다');
    });

    test('모양이 틀리면 null — 산책·주간 정리 payload 도 아니다', () {
      expect(scheduleFocusOf(null), isNull);
      expect(scheduleFocusOf('schedule-reminder:마흔하나:2026-10-20'), isNull);
      expect(scheduleFocusOf('schedule-reminder:41:이십일'), isNull);
      expect(scheduleFocusOf('schedule-reminder:0:2026-10-20'), isNull, reason: '일정 id 는 1부터다');
      expect(scheduleFocusOf(walkReminderPayload), isNull);
      expect(scheduleFocusOf('$weeklyReportPayload:41:2026-10-20'), isNull);
    });

    test('가져가면 비운다 — 일정 탭에 다시 와도 안 끌려간다', () {
      addTearDown(ScheduleFocusInbox.resetForTest);
      ScheduleFocusInbox.offer(ScheduleFocus(scheduleId: 7, onDate: _anyDay));

      expect(ScheduleFocusInbox.take()?.scheduleId, 7);
      expect(ScheduleFocusInbox.take(), isNull);
    });

    test('null 은 적지 않는다 — 있던 것을 지우지도 않는다', () {
      addTearDown(ScheduleFocusInbox.resetForTest);
      ScheduleFocusInbox.offer(ScheduleFocus(scheduleId: 7, onDate: _anyDay));

      ScheduleFocusInbox.offer(null);

      expect(ScheduleFocusInbox.pending.value?.scheduleId, 7);
    });
  });

  group('예약에 싣는 것 (#420 후속)', () {
    ScheduleReminder reminder({int scheduleId = 41}) => ScheduleReminder(
          id: ScheduleReminder.idBase + scheduleId,
          scheduleId: scheduleId,
          onDate: DateTime(2026, 10, 20),
          at: DateTime(2026, 10, 19, 20),
          title: '병원',
          body: '보리 병원 · 14:00',
        );

    test('예약마다 그 일정이 payload 에 실린다 — 종류만 실으면 누른 뒤 갈 곳이 없다', () {
      final planned = scheduleNotificationsFor([reminder(scheduleId: 41)]);

      expect(planned.single.payload, 'schedule-reminder:41:2026-10-20');
      expect(scheduleFocusOf(planned.single.payload)?.scheduleId, 41,
          reason: '싣는 쪽과 읽는 쪽이 같은 규칙을 써야 한다');
    });

    test('id·시각·제목·본문은 그대로 옮긴다', () {
      final planned = scheduleNotificationsFor([reminder()]).single;

      expect(planned.id, ScheduleReminder.idBase + 41);
      expect(planned.at, DateTime(2026, 10, 19, 20));
      expect(planned.title, '병원');
      expect(planned.body, '보리 병원 · 14:00');
    });

    test('누른 알림은 갈 탭과 그 일정을 함께 남긴다', () {
      addTearDown(ScheduleFocusInbox.resetForTest);

      offerFromNotification(scheduleReminderPayloadFor(41, DateTime(2026, 10, 20)));

      expect(NotificationRouteInbox.take(), NotificationDestination.schedule);
      expect(ScheduleFocusInbox.take()?.scheduleId, 41,
          reason: '탭만 남기면 사용자가 그 날을 다시 찾아야 한다');
    });

    test('산책 알림은 갈 탭만 남긴다 — 일정 자리는 비어 있다', () {
      addTearDown(ScheduleFocusInbox.resetForTest);

      offerFromNotification(walkReminderPayload);

      expect(NotificationRouteInbox.take(), NotificationDestination.home);
      expect(ScheduleFocusInbox.take(), isNull);
    });
  });

  group('탭 번호', () {
    test('일정은 일정 탭(2), 나머지는 홈(0)', () {
      expect(tabOf(NotificationDestination.home), 0);
      expect(tabOf(NotificationDestination.schedule), 2);
      expect(tabOf(NotificationDestination.weeklyReport), 0,
          reason: '통계는 탭이 아니라 홈 위에 얹는 화면이다');
    });
  });

  group('받아 두는 곳', () {
    test('적어 두면 가져갈 수 있고, 가져가면 비운다 — 한 번만 간다', () {
      NotificationRouteInbox.offer(NotificationDestination.weeklyReport);

      expect(NotificationRouteInbox.take(), NotificationDestination.weeklyReport);
      expect(NotificationRouteInbox.take(), isNull, reason: '두 번째는 없다');
    });

    test('모르는 곳(null)은 적지 않는다 — 있던 것을 지우지도 않는다', () {
      NotificationRouteInbox.offer(NotificationDestination.home);

      NotificationRouteInbox.offer(null);

      expect(NotificationRouteInbox.pending.value, NotificationDestination.home);
    });

    test('듣고 있으면 적는 순간 알려 준다 — 앱이 떠 있는 동안 누른 알림', () {
      final seen = <NotificationDestination?>[];
      void listener() => seen.add(NotificationRouteInbox.pending.value);
      NotificationRouteInbox.pending.addListener(listener);
      addTearDown(() => NotificationRouteInbox.pending.removeListener(listener));

      NotificationRouteInbox.offer(NotificationDestination.schedule);

      expect(seen, [NotificationDestination.schedule]);
    });
  });
}

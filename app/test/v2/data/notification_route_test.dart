// 알림을 누르면 어디로 (#486 후속) — payload 읽기 · 탭 번호 · 한 번만 간다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/notification_route.dart';

void main() {
  setUp(NotificationRouteInbox.resetForTest);
  tearDown(NotificationRouteInbox.resetForTest);

  group('payload 읽기', () {
    test('세 알림이 각자의 자리로', () {
      expect(destinationOf(walkReminderPayload), NotificationDestination.home);
      expect(destinationOf(scheduleReminderPayload), NotificationDestination.schedule);
      expect(destinationOf(weeklyReportPayload), NotificationDestination.weeklyReport);
    });

    test('payload 가 없거나 모르는 값이면 null — 앱만 열린다', () {
      expect(destinationOf(null), isNull);
      expect(destinationOf(''), isNull);
      expect(destinationOf('무언가-새로운-것'), isNull,
          reason: '알림은 며칠 뒤에 울린다 — 그 사이 앱이 바뀌어도 죽지 않아야 한다');
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

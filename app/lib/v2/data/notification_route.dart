// lib/v2/data/notification_route.dart
//
// 알림을 누르면 그 자리로 — 저녁 산책 알림(#341)은 홈, 일정 알림(#420)은 일정 탭, 일요일 주간 정리(#486
// 후속)는 통계 화면.
//
// ## 일정은 탭까지로 부족하다
//
// "병원 예약" 알림을 눌렀는데 이번 달 달력이 열리면, 사용자는 알림이 말한 그 날을 **다시 찾아야 한다.**
// 그래서 일정 알림의 payload 는 종류만이 아니라 **그 일정의 id 와 그 날**을 싣는다
// (`schedule-reminder:41:2026-10-20`). 탭을 아는 것과 그 안에서 어디를 여는지는 다른 일이라,
// 가는 곳([NotificationRouteInbox])과 그 안의 자리([ScheduleFocusInbox])를 따로 둔다 — 일정 화면은
// 셸이 탭을 바꾼 **뒤에** 뜨므로, 두 번째 것은 화면이 떠서 가져갈 때까지 기다린다.
//
// ## 왜 규칙과 이동을 나누나
//
// 누른 알림이 무엇인지 아는 것(`payload` → [NotificationDestination])은 순수 함수라 시계도 화면도 없이
// 잰다. 실제로 가는 것은 탭과 화면을 아는 쪽(`MainShell`)의 일이다. 한 덩어리로 두면 "무엇을 누르면 어디로"
// 를 재려고 셸을 통째로 띄워야 하고, 그러면 그 테스트는 알림이 아니라 셸을 재게 된다.
//
// ## 왜 한 번 받아 두나
//
// 알림은 **앱이 뜨기 전에** 눌린다(꺼져 있던 앱이 그때 뜬다). 그 순간에는 갈 화면이 아직 없으므로
// [NotificationRouteInbox] 에 적어 두고, 홈이 떠서 가져갈 때 그리 간다. 앱이 이미 떠 있었으면 적는 즉시
// 가져간다 — 같은 길이다.
library;

import 'package:flutter/foundation.dart';

import '../domain/schedule_reminder.dart';

/// 알림이 가리키는 곳.
enum NotificationDestination {
  /// 저녁 산책 알림(#341) — 홈. "산책 시작" 이 거기 있다.
  home,

  /// 일정 알림(#420) — 일정 탭.
  schedule,

  /// 일요일 저녁 주간 정리(#486 후속) — 홈 위에 통계 화면.
  weeklyReport,
}

/// 저녁 산책 알림의 payload.
const String walkReminderPayload = 'walk-reminder';

/// 일정 알림 payload 의 **앞머리**. 뒤에 `:<일정 id>:<yyyy-MM-dd>` 가 붙는다
/// ([scheduleReminderPayloadFor]). 옛 버전이 걸어 둔 알림은 이 값 그대로 온다 — 그때는 탭까지만 간다.
const String scheduleReminderPayload = 'schedule-reminder';

/// 일요일 저녁 주간 정리의 payload.
const String weeklyReportPayload = 'weekly-report';

/// payload → 갈 곳. **모르는 값은 null** 이고 그때는 앱만 열린다 — 옛 버전이 걸어 둔 알림(payload 없음)이
/// 그렇다. 알림은 몇 시간에서 며칠 뒤에 울리므로 그 사이에 앱이 바뀐다.
NotificationDestination? destinationOf(String? payload) {
  // 앞머리만 본다 — 일정 알림은 뒤에 id 와 날짜를 달고 온다. 통째로 비교하면 새 payload 를 모르는 값으로
  // 읽어 앱만 열린다(옛 앱이 새 알림을 받는 경우가 정확히 그 모양이라, 그쪽은 그대로 둔다).
  switch (payload?.split(':').first) {
    case walkReminderPayload:
      return NotificationDestination.home;
    case scheduleReminderPayload:
      return NotificationDestination.schedule;
    case weeklyReportPayload:
      return NotificationDestination.weeklyReport;
    default:
      return null;
  }
}

/// 그곳의 탭 번호 — 홈 0 · 지도 1 · 일정 2 · 커뮤니티 3 · 채팅 4(`RootTab`).
///
/// 통계는 탭이 아니라 홈 위에 얹는 화면이라 홈(0)을 돌려준다. 화면을 여는 것은 부르는 쪽의 일이다.
int tabOf(NotificationDestination destination) {
  switch (destination) {
    case NotificationDestination.schedule:
      return 2;
    case NotificationDestination.home:
    case NotificationDestination.weeklyReport:
      return 0;
  }
}

/// 일정 알림이 가리키는 **그 일정** — 이슈 #420 후속.
///
/// [onDate] 는 되풀이하는 일정에도 답을 준다 — id 하나로는 "어느 날의 그것" 을 못 정한다. 날짜만 담고
/// 시각은 안 담는다: 화면이 여는 것은 하루이고, 그 안에서 줄 하나를 [scheduleId] 로 고른다.
class ScheduleFocus {
  const ScheduleFocus({required this.scheduleId, required this.onDate});

  final int scheduleId;

  /// 그 일정이 있는 날(자정). 달이 다르면 화면이 그 달을 다시 읽는다.
  final DateTime onDate;

  @override
  bool operator ==(Object other) =>
      other is ScheduleFocus && other.scheduleId == scheduleId && other.onDate == onDate;

  @override
  int get hashCode => Object.hash(scheduleId, onDate);

  @override
  String toString() => 'ScheduleFocus($scheduleId, $onDate)';
}

/// 일정 알림의 payload — `schedule-reminder:<일정 id>:<yyyy-MM-dd>`.
///
/// 날짜를 문자열로 굳이 싣는 이유: 알림은 며칠 뒤에 울리고 그 사이에 앱이 꺼져 있다. 그때 서버에 물어
/// 날짜를 알아내려면 화면이 뜨기도 전에 네트워크가 필요하고, 실패하면 아무 데도 못 간다.
String scheduleReminderPayloadFor(int scheduleId, DateTime onDate) =>
    '$scheduleReminderPayload:$scheduleId:${_ymd(onDate)}';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// payload 에서 그 일정을 읽는다. **모양이 조금이라도 다르면 null** — 그때는 탭까지만 간다.
///
/// 옛 알림(`schedule-reminder` 만)도 여기서 null 이다. 못 읽은 것을 오류로 만들지 않는 이유는
/// [destinationOf] 와 같다 — 알림은 앱보다 오래 산다.
ScheduleFocus? scheduleFocusOf(String? payload) {
  if (payload == null) return null;
  final parts = payload.split(':');
  if (parts.length != 3 || parts.first != scheduleReminderPayload) return null;
  final id = int.tryParse(parts[1]);
  final date = DateTime.tryParse(parts[2]);
  if (id == null || id <= 0 || date == null) return null;
  return ScheduleFocus(scheduleId: id, onDate: DateTime(date.year, date.month, date.day));
}

/// 예약 한 건이 플러그인에 실리는 모양 — id · 시각 · 제목 · 본문 · payload.
///
/// **정책을 싱크에서 떼어 낸 자리다.** `LocalNotificationSink` 는 플러그인을 아는 유일한 파일이고
/// 그래서 테스트가 그 파일을 import 하지 않는다 — 그 안에 "무엇을 싣는가" 가 있으면 아무도 못 잰다.
/// 실제로 payload 에서 일정 id 를 빼 보고도 테스트가 초록이었다(되돌려서 빨간불 F1).
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

/// 일정 알림 예약들 — 각자의 payload 에 **그 일정**을 싣는다(#420 후속).
List<ScheduledNotification> scheduleNotificationsFor(List<ScheduleReminder> reminders) =>
    reminders
        .map((r) => ScheduledNotification(
              id: r.id,
              at: r.at,
              title: r.title,
              body: r.body,
              payload: scheduleReminderPayloadFor(r.scheduleId, r.onDate),
            ))
        .toList(growable: false);

/// 알림을 눌렀다 — **갈 탭**과, 일정이면 **그 안의 그 날**을 적어 둔다.
///
/// 상자가 둘인 이유는 가져가는 사람이 다르기 때문이다(아래 두 클래스). 여기서는 적어 두기만 한다 —
/// 이 순간에는 아직 화면이 없을 수도 있다(꺼져 있던 앱이 알림으로 뜨는 경우).
void offerFromNotification(String? payload) {
  NotificationRouteInbox.offer(destinationOf(payload));
  ScheduleFocusInbox.offer(scheduleFocusOf(payload));
}

/// 누른 알림이 남긴 "아직 못 간 곳".
///
/// 값을 [take] 하면 비운다 — **한 번만 간다.** 비우지 않으면 홈이 다시 그려질 때마다 같은 곳으로 끌려가
/// 사용자가 다른 탭에 머물 수 없다.
class NotificationRouteInbox {
  const NotificationRouteInbox._();

  /// 지금 갈 곳(없으면 null). 화면이 이것을 듣고 있다가 가져간다.
  static final ValueNotifier<NotificationDestination?> pending =
      ValueNotifier<NotificationDestination?>(null);

  /// 알림이 눌렸다. 모르는 곳(null)이면 아무 일도 없다 — 앱만 열린다.
  static void offer(NotificationDestination? destination) {
    if (destination == null) return;
    pending.value = destination;
  }

  /// 가져가고 비운다. 없으면 null.
  static NotificationDestination? take() {
    final destination = pending.value;
    pending.value = null;
    return destination;
  }

  /// 테스트 사이에 새는 것을 막는다 — 정적 상태를 쓰는 대가다.
  @visibleForTesting
  static void resetForTest() => pending.value = null;
}

/// 일정 화면이 열릴 때 가져갈 "그 일정".
///
/// [NotificationRouteInbox] 와 나눠 둔 이유는 **가져가는 사람이 다르기** 때문이다 — 탭은 셸이 바로
/// 바꾸지만, 그 날을 여는 것은 그때 처음 뜨는 일정 화면이다. 한 상자에 담으면 셸이 먼저 비워
/// 일정 화면은 빈손으로 뜬다.
class ScheduleFocusInbox {
  const ScheduleFocusInbox._();

  static final ValueNotifier<ScheduleFocus?> pending = ValueNotifier<ScheduleFocus?>(null);

  /// 알림이 그 일정을 가리켰다. null 이면 아무 일도 없다 — 있던 것을 지우지도 않는다.
  static void offer(ScheduleFocus? focus) {
    if (focus == null) return;
    pending.value = focus;
  }

  /// 가져가고 비운다. **한 번만 간다** — 안 비우면 일정 탭에 올 때마다 그 날로 끌려간다.
  static ScheduleFocus? take() {
    final focus = pending.value;
    pending.value = null;
    return focus;
  }

  @visibleForTesting
  static void resetForTest() => pending.value = null;
}

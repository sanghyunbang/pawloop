// lib/v2/data/notification_route.dart
//
// 알림을 누르면 그 자리로 — 저녁 산책 알림(#341)은 홈, 일정 알림(#420)은 일정 탭, 일요일 주간 정리(#486
// 후속)는 통계 화면.
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

/// 일정 알림의 payload.
const String scheduleReminderPayload = 'schedule-reminder';

/// 일요일 저녁 주간 정리의 payload.
const String weeklyReportPayload = 'weekly-report';

/// payload → 갈 곳. **모르는 값은 null** 이고 그때는 앱만 열린다 — 옛 버전이 걸어 둔 알림(payload 없음)이
/// 그렇다. 알림은 몇 시간에서 며칠 뒤에 울리므로 그 사이에 앱이 바뀐다.
NotificationDestination? destinationOf(String? payload) {
  switch (payload) {
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

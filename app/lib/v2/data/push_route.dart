// lib/v2/data/push_route.dart
//
// 서버 푸시(FCM)의 data → 우리 알림 payload — 이슈 #83.
//
// ## 푸시라고 다른 길을 내지 않는다
//
// 서버는 `PushMessage` 에 종류(`kind`)와 그 종류의 식별자만 싣는다 — `chat.message` 는
// roomId·roomSeq·messageId, `schedule.assigned` 는 scheduleId·onDate. 앱은 그것을 **기기 알림이
// 이미 쓰는 payload**(`notification_route.dart`)로 바꾼다. 그러면 누른 뒤의 길이 하나다:
// `offerFromNotification` → `NotificationRouteInbox` → `MainShell`. 푸시용 길을 따로 내면
// "일정 알림을 누르면 그 날이 열린다" 가 푸시에서만 안 되는 날이 온다.
//
// ## 이 파일은 firebase 를 모른다
//
// 플러그인을 아는 파일은 `firebase_push.dart` 하나다. 여기가 순수해야 순수 테스트가 "무슨 data 가
// 오면 어디로 가는가" 를 시계도 채널도 없이 잰다. 모르는 종류·틀린 모양은 **null** — 그때는 앱만
// 열린다. 푸시는 서버가 앱보다 먼저 바뀔 수 있어서, 모르는 것으로 죽으면 안 된다.
library;

import 'notification_route.dart';

/// 서버가 싣는 종류 — `PushMessage` 의 `kind` 와 같은 문자열이다.
const String pushKindChatMessage = 'chat.message';
const String pushKindScheduleAssigned = 'schedule.assigned';

/// 푸시의 data → 우리 payload. **모르는 종류나 틀린 모양이면 null** — 그때는 앱만 열린다.
///
/// 일정 배정은 `schedule-reminder:<일정 id>:<yyyy-MM-dd>` 가 된다 — 기기의 일정 알림과 같은
/// 모양이라 누르면 **그 날의 그 줄**까지 간다(#420 후속). 채팅은 `chat-message:<방 id>`.
String? pushPayloadOf(Map<String, Object?> data) {
  switch (data['kind']) {
    case pushKindScheduleAssigned:
      final id = _positiveInt(data['scheduleId']);
      final date = DateTime.tryParse('${data['onDate'] ?? ''}');
      if (id == null || date == null) return null;
      return scheduleReminderPayloadFor(id, date);
    case pushKindChatMessage:
      final roomId = _positiveInt(data['roomId']);
      if (roomId == null) return null;
      return chatMessagePayloadFor(roomId);
    default:
      return null;
  }
}

int? _positiveInt(Object? value) {
  final n = value is int ? value : int.tryParse('${value ?? ''}'.trim());
  if (n == null || n <= 0) return null;
  return n;
}

/// 앱이 **앞에 떠 있을 때** 온 푸시를 기기 알림으로 보여 줄 내용.
///
/// 뒤에 있을 때는 FCM 이 직접 띄우므로 이것이 필요 없다. 앞에 있을 때는 아무도 안 띄워서
/// — 소리도 배너도 없이 조용히 사라진다 — 우리가 같은 제목·본문으로 한 장 띄운다.
class ForegroundNotice {
  const ForegroundNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// 알림 번호. 같은 방·같은 일정이면 같은 번호라 **겹치지 않고 바뀐다** — 채팅 한 방에서 다섯 통이
  /// 오면 알림은 다섯 장이 아니라 마지막 한 장이다.
  final int id;
  final String title;
  final String body;

  /// 누르면 갈 곳. 모르는 종류면 null(앱만 열린다).
  final String? payload;
}

/// 산책(341) · 주간 정리(486) · 일정(일정 id)과 겹치지 않는 번호 대역.
const int _chatNoticeBase = 8300000;
const int _scheduleNoticeBase = 8400000;
const int _otherNoticeId = 83;

/// 앞에 떠 있을 때 온 푸시 → 보여 줄 것. **제목이 없으면 null** — 보여 줄 것이 없다.
///
/// 제목·본문은 서버가 보낸 것을 그대로 쓴다(`PushMessage.forChatMessage` 등이 문장을 정한다).
/// 앱이 다시 만들면 뒤에서 온 것(FCM 이 띄움)과 앞에서 온 것(우리가 띄움)의 문장이 갈린다.
ForegroundNotice? foregroundNoticeOf({
  required Map<String, Object?> data,
  String? title,
  String? body,
}) {
  final heading = title?.trim() ?? '';
  if (heading.isEmpty) return null;
  return ForegroundNotice(
    id: _noticeIdOf(data),
    title: heading,
    body: body?.trim() ?? '',
    payload: pushPayloadOf(data),
  );
}

int _noticeIdOf(Map<String, Object?> data) {
  switch (data['kind']) {
    case pushKindChatMessage:
      final roomId = _positiveInt(data['roomId']);
      return roomId == null ? _otherNoticeId : _chatNoticeBase + roomId % 100000;
    case pushKindScheduleAssigned:
      final scheduleId = _positiveInt(data['scheduleId']);
      return scheduleId == null ? _otherNoticeId : _scheduleNoticeBase + scheduleId % 100000;
    default:
      return _otherNoticeId;
  }
}

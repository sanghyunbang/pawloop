// 일정 알림의 **규칙** — 이슈 #420 (부모 #416).
//
// ## 기기 로컬이다
//
// 푸시(#83)는 서버가 보내지만 이 알림은 **이 기기가 스스로** 건다. 그래서 담당자가 다른
// 사람이면 **그 사람 기기에는 안 뜬다.** 만들기 시트가 그 한계를 한 줄로 말한다 — 안 말하면
// 사용자는 "아빠 담당" 이라고 적어 두고 아빠가 알림을 받을 거라고 믿는다.
//
// ## 규칙만 여기 있다
//
// `walk_reminder.dart` 와 같은 방식이다 — 플러그인을 아는 파일은 `local_notification_sink`
// 하나뿐이고, 여기는 순수 함수라 위젯 테스트가 그대로 부를 수 있다.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'schedule.dart';

/// 언제 알릴까.
enum ScheduleReminderWhen {
  /// 안 알린다. **기본값이다** — 묻지 않고 알림을 보내는 앱이 되면 안 된다.
  none('none', '없음'),

  /// 전날 저녁 8시. 준비할 것이 있는 일정(병원·미용)에 맞는 자리다.
  eveningBefore('evening_before', '전날 저녁'),

  /// 당일 아침 8시. 그날 안에 하면 되는 것(약·목욕)에 맞다.
  morningOf('morning_of', '당일 아침');

  const ScheduleReminderWhen(this.wire, this.label);

  final String wire;
  final String label;

  static ScheduleReminderWhen parse(Object? value) {
    for (final w in values) {
      if (w.wire == value) return w;
    }
    return ScheduleReminderWhen.none;
  }
}

/// 설정이 바뀐 횟수. 설정 화면이 저장하면 올라가고, 예약을 다시 거는 쪽이 그것을 본다.
final ValueNotifier<int> kScheduleReminderRev = ValueNotifier<int>(0);

class ScheduleReminderStore {
  const ScheduleReminderStore();

  static const _key = 'v2.schedule_reminder';

  Future<ScheduleReminderWhen> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return ScheduleReminderWhen.none;
    try {
      final json = jsonDecode(raw);
      return ScheduleReminderWhen.parse(json is Map ? json['when'] : null);
    } on FormatException {
      return ScheduleReminderWhen.none;
    }
  }

  Future<void> save(ScheduleReminderWhen when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'when': when.wire}));
    kScheduleReminderRev.value++;
  }
}

/// 알림을 실제로 거는 자리. 테스트는 이것을 가짜로 갈아끼운다.
///
/// **인터페이스가 여기(순수 파일)에 있는 것은 의도다.** 구현은
/// `data/local_notification_sink.dart` 이고 그 파일은 `flutter_local_notifications` 를
/// 부른다 — 화면이 그것을 import 하면 위젯 테스트가 채널 없이 던진다.
///
/// **산책 알림(#341)과 달리 여러 건이다.** 그래서 `cancelAll` 이 아니라 "지난번에 건 것들을
/// 거두고 이번 것들을 건다" 는 모양이다 — 어느 일정이 사라졌는지 부르는 쪽이 모른다.
abstract class ScheduleReminderSink {
  Future<void> replaceAll(List<ScheduleReminder> reminders);
}

/// 예약 하나 — 언제, 무엇을.
class ScheduleReminder {
  /// 알림 id. **일정 id 에서 파생한다** — 그래야 같은 일정을 두 번 걸어도 하나만 남는다.
  final int id;

  final DateTime at;
  final String title;
  final String body;

  /// 이 알림이 가리키는 일정. 누르면 그 일정이 있는 날이 열린다(#420 후속).
  ///
  /// [id] 에서 빼서 구할 수도 있지만(그 값이 `idBase + scheduleId` 다) 그러면 알림 id 규칙이
  /// **두 곳의 약속**이 된다 — 한쪽을 바꾸는 날 다른 쪽이 조용히 틀린다.
  final int scheduleId;

  /// 그 일정이 있는 날(자정). 되풀이하는 일정은 id 하나로 "어느 날" 을 못 정한다.
  final DateTime onDate;

  const ScheduleReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.scheduleId,
    required this.onDate,
  });

  /// 산책 알림(#341)이 쓰는 `341` 과 겹치지 않게 띄워 둔 자리.
  ///
  /// 안드로이드의 알림 id 는 32비트 정수라 큰 수를 못 쓴다. 일정 id 를 그대로 쓰면
  /// 언젠가 341 과 부딪히고, 그러면 저녁 산책 알림이 조용히 사라진다.
  static const int idBase = 420000;

  /// id 가 넘칠 수 있는 자리를 여기 한 번만 적어 둔다 — 일정 id 가 이만큼 커지면
  /// 다른 방법이 필요하다(그때는 이 상수가 그 사실을 말해 준다).
  static const int maxScheduleId = 1000000;

  @override
  bool operator ==(Object other) =>
      other is ScheduleReminder &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.scheduleId == scheduleId &&
      other.onDate == onDate;

  @override
  int get hashCode => Object.hash(id, at, title, body, scheduleId, onDate);

  @override
  String toString() => 'ScheduleReminder($id, $at, $title, #$scheduleId ${onDate.month}/${onDate.day})';
}

/// 이 일정들에 걸 알림.
///
/// 규칙 넷이 여기 다 있다.
///
///  1. **`none` 이면 하나도 안 건다.**
///  2. **이미 한 것·건너뛴 것은 안 건다** — 알림은 앞으로 할 일에만 온다.
///  3. **지나간 시각에는 안 건다.** 지난 시각에 지금 울리면 그건 알림이 아니라 잔소리다.
///  4. id 가 [ScheduleReminder.maxScheduleId] 를 넘으면 건너뛴다 — 산책 알림 id 와 부딪히느니
///     그 하나를 안 거는 쪽이 낫다.
///
/// 본문은 **제목**이다. 종류가 아니라 제목인 이유는, 알림은 한 건이라 자리가 있고 사용자가
/// 자기 문장을 그대로 보는 편이 무엇인지 빨리 알기 때문이다(홈의 한 줄은 반대로 종류를 쓴다 —
/// 거기는 여럿이 한 줄에 들어간다).
List<ScheduleReminder> planReminders({
  required List<Schedule> schedules,
  required ScheduleReminderWhen when,
  required DateTime now,
}) {
  if (when == ScheduleReminderWhen.none) return const [];

  final out = <ScheduleReminder>[];
  for (final s in schedules) {
    if (!s.status.isOpen) continue;
    if (s.id <= 0 || s.id >= ScheduleReminder.maxScheduleId) continue;

    final at = switch (when) {
      ScheduleReminderWhen.eveningBefore =>
        DateTime(s.onDate.year, s.onDate.month, s.onDate.day - 1, 20),
      ScheduleReminderWhen.morningOf =>
        DateTime(s.onDate.year, s.onDate.month, s.onDate.day, 8),
      ScheduleReminderWhen.none => null,
    };
    if (at == null || !at.isAfter(now)) continue;

    out.add(ScheduleReminder(
      id: ScheduleReminder.idBase + s.id,
      scheduleId: s.id,
      onDate: DateTime(s.onDate.year, s.onDate.month, s.onDate.day),
      at: at,
      title: s.kind.label,
      body: s.isAllDay
          ? s.title
          : '${s.title} · ${Schedule.formatTime(s.atTime!)}',
    ));
  }
  return out;
}

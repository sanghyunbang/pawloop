// 채팅방의 읽기 흐름 — 말풍선 묶기 · 날짜 구분선 (#452).
//
// 카카오톡의 규칙을 따른다: 같은 사람이 **같은 분(minute)** 에 이어 보낸 말은 한 묶음이다 —
// 이름 · 아바타는 묶음의 첫 말에만, 시각은 묶음의 마지막 말에만. 날이 바뀌면 가운데에
// "2026년 9월 14일 월요일" 구분선. iMessage · Instagram DM 도 같은 모양이다(묶음 안은 촘촘, 묶음
// 사이는 넓게).
//
// 이 파일은 순수 함수다 — 화면은 [layoutThread] 의 결과를 그리기만 한다. 시계 · 네트워크 · 위젯을
// 모르므로 값으로 잰다(`chat_thread_test`).

/// 말 하나의 재료 — 누가([senderKey]) 언제([at]). 보내는 중인 말은 내 말이라 [senderKey] 가 나다.
class ThreadEntry {
  final String senderKey;
  final DateTime? at;

  const ThreadEntry({required this.senderKey, required this.at});
}

/// 말 하나를 어떻게 그릴지.
class ThreadSlot {
  /// 이 말 **위에** 날짜 구분선을 둔다 — 첫 말이거나 앞 말과 날이 다르다. 없으면 null.
  final String? dayLabel;

  /// 이름 · 아바타를 그린다 — 묶음의 첫 말.
  final bool showHeader;

  /// 시각을 그린다 — 묶음의 마지막 말.
  final bool showTime;

  /// 앞 말과 같은 묶음이라 간격을 좁힌다.
  final bool tight;

  const ThreadSlot({
    required this.dayLabel,
    required this.showHeader,
    required this.showTime,
    required this.tight,
  });
}

/// 시각이 없는 말(아직 서버가 번호를 안 준 것)은 [now] 로 본다.
List<ThreadSlot> layoutThread(List<ThreadEntry> entries, {required DateTime now}) {
  final out = <ThreadSlot>[];
  for (var i = 0; i < entries.length; i++) {
    final cur = entries[i];
    final prev = i > 0 ? entries[i - 1] : null;
    final next = i + 1 < entries.length ? entries[i + 1] : null;
    final at = (cur.at ?? now).toLocal();
    final dayStart = prev == null || !_sameDay((prev.at ?? now).toLocal(), at);
    final continues = prev != null && !dayStart && prev.senderKey == cur.senderKey && _sameMinute((prev.at ?? now).toLocal(), at);
    final continued = next != null &&
        next.senderKey == cur.senderKey &&
        _sameMinute(at, (next.at ?? now).toLocal()) &&
        _sameDay(at, (next.at ?? now).toLocal());
    out.add(ThreadSlot(
      dayLabel: dayStart ? dayLabelOf(at) : null,
      showHeader: !continues,
      showTime: !continued,
      tight: continues,
    ));
  }
  return out;
}

/// "2026년 9월 14일 월요일" — 카카오톡의 날짜 구분선 그대로. intl 없이 만든다(로케일 초기화에
/// 기대지 않는다).
String dayLabelOf(DateTime local) {
  const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return '${local.year}년 ${local.month}월 ${local.day}일 ${weekdays[local.weekday - 1]}';
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameMinute(DateTime a, DateTime b) => _sameDay(a, b) && a.hour == b.hour && a.minute == b.minute;

/// 방 목록의 시각 한 조각(#452) — 카카오톡 · 당근의 규칙. 오늘이면 `HH:mm`, 어제면 "어제", 올해면
/// "9월 12일", 그보다 전이면 "2025. 9. 12.". 기기 시간대로 본다.
String chatListTimeLabel(DateTime at, {required DateTime now}) {
  final a = at.toLocal();
  final n = now.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(a.year, a.month, a.day);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    return '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
  }
  if (days == 1) return '어제';
  if (a.year == n.year) return '${a.month}월 ${a.day}일';
  return '${a.year}. ${a.month}. ${a.day}.';
}


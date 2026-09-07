// 커뮤니티 목록·상세가 함께 쓰는 날짜 표기 (#331).
//
// 전에는 "26.09.06" 이었다 — 두 자리 연도는 날짜인지 버전인지 읽는 사람이 한 번 더 생각한다.
// 올해면 연도를 빼고 "9월 6일", 다른 해면 "2025. 9. 6". 시각은 채팅 말풍선과 같은 두 자리
// `HH:mm` 이다. 서버 시각은 UTC 로 오므로 먼저 기기 시간대로 바꾼다.

/// "9월 6일"(올해) / "2025. 9. 6"(다른 해). [now] 는 테스트가 고정한다.
String dateLabel(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = now ?? DateTime.now();
  if (local.year == today.year) return '${local.month}월 ${local.day}일';
  return '${local.year}. ${local.month}. ${local.day}';
}

/// "9월 6일 14:20" — 날짜는 [dateLabel], 시각은 채팅과 같은 `HH:mm`.
String dateTimeLabel(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final hh = '${local.hour}'.padLeft(2, '0');
  final mm = '${local.minute}'.padLeft(2, '0');
  return '${dateLabel(local, now: now)} $hh:$mm';
}

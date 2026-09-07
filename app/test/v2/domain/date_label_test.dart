// 날짜 표기 — 올해는 "9월 6일", 다른 해는 "2025. 9. 6", 두 자리 연도는 없다 (#331).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/date_label.dart';

void main() {
  final now = DateTime(2026, 9, 7, 12);

  test('올해면 연도를 빼고 "9월 6일"', () {
    expect(dateLabel(DateTime(2026, 9, 6, 14, 20), now: now), '9월 6일');
    expect(dateLabel(DateTime(2026, 1, 1), now: now), '1월 1일');
  });

  test('다른 해면 "2025. 9. 6" — 두 자리 연도 "25.09.06" 이 아니다', () {
    expect(dateLabel(DateTime(2025, 9, 6), now: now), '2025. 9. 6');
    expect(dateLabel(DateTime(2027, 12, 31), now: now), '2027. 12. 31');
  });

  test('시각이 붙으면 채팅과 같은 두 자리 HH:mm', () {
    expect(dateTimeLabel(DateTime(2026, 9, 6, 9, 5), now: now), '9월 6일 09:05');
    expect(dateTimeLabel(DateTime(2025, 9, 6, 14, 20), now: now), '2025. 9. 6 14:20');
  });

  test('UTC 로 온 서버 시각은 기기 시간대로 바꿔 그린다', () {
    final utc = DateTime.utc(2026, 9, 6, 5, 30);
    expect(dateTimeLabel(utc, now: now), dateTimeLabel(utc.toLocal(), now: now));
    expect(dateTimeLabel(utc, now: now), endsWith(':30'));
  });
}

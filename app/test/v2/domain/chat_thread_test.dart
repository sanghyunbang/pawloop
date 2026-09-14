// 말풍선 묶기 · 날짜 구분선 (#452) — 값으로 잰다.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/chat_thread.dart';

void main() {
  final now = DateTime(2026, 9, 14, 21, 0);
  ThreadEntry e(String who, DateTime at) => ThreadEntry(senderKey: who, at: at);
  DateTime t(int h, int m, [int s = 0]) => DateTime(2026, 9, 14, h, m, s);

  test('같은 사람이 같은 분에 이어 보내면 한 묶음 — 이름은 첫 말에만, 시각은 마지막 말에만', () {
    final slots = layoutThread([
      e('보리', t(9, 5, 1)),
      e('보리', t(9, 5, 20)),
      e('보리', t(9, 5, 59)),
    ], now: now);

    expect(slots.map((s) => s.showHeader), [true, false, false]);
    expect(slots.map((s) => s.showTime), [false, false, true]);
    expect(slots.map((s) => s.tight), [false, true, true]);
  });

  test('사람이 바뀌면 새 묶음 — 앞 묶음의 마지막에 시각, 새 묶음의 첫 말에 이름', () {
    final slots = layoutThread([
      e('보리', t(9, 5)),
      e('콩이', t(9, 5)),
    ], now: now);

    expect(slots[0].showTime, isTrue);
    expect(slots[1].showHeader, isTrue);
    expect(slots[1].tight, isFalse);
  });

  test('분이 바뀌면 같은 사람이어도 시각을 다시 적는다 — 카카오톡과 같다', () {
    final slots = layoutThread([
      e('보리', t(9, 5, 50)),
      e('보리', t(9, 6, 10)),
    ], now: now);

    expect(slots[0].showTime, isTrue);
    expect(slots[1].showHeader, isTrue, reason: '분이 다르면 새 묶음이다 — 시각이 두 번 보이는 것이 맞다');
  });

  test('날이 바뀌면 그 말 위에 날짜 구분선, 같은 날에는 없다 · 첫 말에는 늘 있다', () {
    final slots = layoutThread([
      e('보리', DateTime(2026, 9, 13, 23, 59)),
      e('보리', DateTime(2026, 9, 14, 0, 0)),
      e('보리', DateTime(2026, 9, 14, 0, 0, 30)),
    ], now: now);

    expect(slots[0].dayLabel, '2026년 9월 13일 일요일');
    expect(slots[1].dayLabel, '2026년 9월 14일 월요일');
    expect(slots[2].dayLabel, isNull);
    expect(slots[1].showHeader, isTrue, reason: '날이 바뀌면 같은 사람이어도 이름을 다시 쓴다');
    expect(slots[0].showTime, isTrue);
  });

  test('요일 이름 — 월~일', () {
    expect(dayLabelOf(DateTime(2026, 9, 14)), endsWith('월요일'));
    expect(dayLabelOf(DateTime(2026, 9, 20)), endsWith('일요일'));
    expect(dayLabelOf(DateTime(2026, 1, 3)), '2026년 1월 3일 토요일');
  });

  test('시각이 없는 말(보내는 중)은 지금으로 본다 — 내 마지막 말과 같은 분이면 같은 묶음', () {
    final slots = layoutThread([
      e('나', DateTime(2026, 9, 14, 21, 0, 10)),
      const ThreadEntry(senderKey: '나', at: null),
    ], now: now);

    expect(slots[1].tight, isTrue);
    expect(slots[0].showTime, isFalse);
    expect(slots[1].showTime, isTrue);
  });

  test('빈 목록은 빈 목록', () {
    expect(layoutThread(const [], now: now), isEmpty);
  });

  test('시각은 기기 시간대로 본다 — UTC 로 온 두 말이 같은 분이면 묶인다', () {
    final slots = layoutThread([
      e('보리', DateTime.utc(2026, 9, 14, 0, 5, 1)),
      e('보리', DateTime.utc(2026, 9, 14, 0, 5, 40)),
    ], now: now);

    expect(slots[1].tight, isTrue);
  });

  // ── 방 목록의 시각 (#452) ──────────────────────────────────
  group('chatListTimeLabel', () {
    final now = DateTime(2026, 9, 14, 21, 5);

    test('오늘이면 HH:mm — 자정 직후의 말도 "오늘" 이다', () {
      expect(chatListTimeLabel(DateTime(2026, 9, 14, 9, 7), now: now), '09:07');
      expect(chatListTimeLabel(DateTime(2026, 9, 14, 0, 0), now: now), '00:00');
    });

    test('어제면 "어제" — 시각은 안 쓴다(카카오톡 · 당근)', () {
      expect(chatListTimeLabel(DateTime(2026, 9, 13, 23, 59), now: now), '어제');
    });

    test('올해 안이면 "9월 12일", 해가 다르면 "2025. 9. 12."', () {
      expect(chatListTimeLabel(DateTime(2026, 9, 12, 8, 0), now: now), '9월 12일');
      expect(chatListTimeLabel(DateTime(2026, 1, 3), now: now), '1월 3일');
      expect(chatListTimeLabel(DateTime(2025, 9, 12), now: now), '2025. 9. 12.');
    });

    test('UTC 로 온 시각도 기기 시간대로 본다', () {
      final at = DateTime.utc(2026, 9, 14, 0, 5); // 로컬로 바꿔 오늘인지 어제인지 판단한다
      final local = at.toLocal();
      final expected = DateTime(local.year, local.month, local.day) == DateTime(now.year, now.month, now.day)
          ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
          : (DateTime(now.year, now.month, now.day).difference(DateTime(local.year, local.month, local.day)).inDays == 1
              ? '어제'
              : '${local.month}월 ${local.day}일');
      expect(chatListTimeLabel(at, now: now), expected);
    });
  });
}

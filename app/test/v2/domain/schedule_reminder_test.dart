// 일정 알림의 규칙 — 이슈 #420.
//
// 순수 함수라 플러그인 없이 잰다. 실제로 거는 자리(`local_notification_sink`)는 위젯
// 테스트에서 가짜로 갈아끼운다 — 진짜는 테스트 바인딩에 채널이 없어 던진다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/schedule.dart';
import 'package:heat_trip_flutter/v2/domain/schedule_reminder.dart';

Schedule _schedule({
  int id = 1,
  String kind = 'vet',
  String title = '보리 병원',
  String onDate = '2026-10-20',
  Object? atTime = '10:30:00',
  String status = 'planned',
  Object? assignee,
}) =>
    Schedule.tryParse({
      'id': id,
      'ownerKind': 'group',
      'ownerRef': 3,
      'kind': kind,
      'title': title,
      'onDate': onDate,
      'atTime': atTime,
      'assignee': assignee,
      'status': status,
      'version': 0,
    })!;

const _me = {'userId': 5, 'nickname': '엄마'};
const _dad = {'userId': 6, 'nickname': '아빠'};

final _now = DateTime(2026, 10, 15, 9);

void main() {
  test('없음이면 하나도 안 건다', () {
    final plan = planReminders(
      schedules: [_schedule()],
      when: ScheduleReminderWhen.none,
      now: _now,
    );

    expect(plan, isEmpty);
  });

  test('전날 저녁 8시', () {
    final plan = planReminders(
      schedules: [_schedule(onDate: '2026-10-20')],
      when: ScheduleReminderWhen.eveningBefore,
      now: _now,
    );

    expect(plan.single.at, DateTime(2026, 10, 19, 20));
  });

  test('당일 아침 8시', () {
    final plan = planReminders(
      schedules: [_schedule(onDate: '2026-10-20')],
      when: ScheduleReminderWhen.morningOf,
      now: _now,
    );

    expect(plan.single.at, DateTime(2026, 10, 20, 8));
  });

  test('지나간 시각에는 안 건다 — 지금 울리면 알림이 아니라 잔소리다', () {
    final plan = planReminders(
      // 어제 것. 전날 저녁은 그저께다.
      schedules: [_schedule(onDate: '2026-10-14')],
      when: ScheduleReminderWhen.eveningBefore,
      now: _now,
    );

    expect(plan, isEmpty);
  });

  test('오늘 아침 8시는 이미 지났다 — 지금이 9시다', () {
    final plan = planReminders(
      schedules: [_schedule(onDate: '2026-10-15')],
      when: ScheduleReminderWhen.morningOf,
      now: _now,
    );

    expect(plan, isEmpty);
  });

  test('이미 한 것과 건너뛴 것은 안 건다', () {
    final plan = planReminders(
      schedules: [
        _schedule(id: 1, status: 'done'),
        _schedule(id: 2, status: 'skipped'),
        _schedule(id: 3, status: 'planned'),
      ],
      when: ScheduleReminderWhen.morningOf,
      now: _now,
    );

    expect(plan.map((r) => r.id), [ScheduleReminder.idBase + 3]);
  });

  test('알림 id 가 산책 알림(341)과 안 부딪힌다', () {
    final plan = planReminders(
      schedules: [_schedule(id: 341)],
      when: ScheduleReminderWhen.morningOf,
      now: _now,
    );

    expect(plan.single.id, isNot(341),
        reason: '부딪히면 저녁 산책 알림이 조용히 사라진다');
    expect(plan.single.id, ScheduleReminder.idBase + 341);
  });

  test('일정 id 가 너무 크면 건너뛴다 — 부딪히느니 하나를 안 거는 쪽이 낫다', () {
    final plan = planReminders(
      schedules: [_schedule(id: ScheduleReminder.maxScheduleId)],
      when: ScheduleReminderWhen.morningOf,
      now: _now,
    );

    expect(plan, isEmpty);
  });

  group('본문', () {
    test('시각이 있으면 제목과 함께 적는다', () {
      final plan = planReminders(
        schedules: [_schedule(title: '보리 병원', atTime: '14:00:00')],
        when: ScheduleReminderWhen.morningOf,
        now: _now,
      );

      expect(plan.single.scheduleId, isPositive,
          reason: '누르면 그 일정이 있는 날이 열린다(#420 후속) — 알림 id 에서 빼서 구하지 않는다');
      expect(plan.single.title, '병원');
      expect(plan.single.body, '보리 병원 · 14:00');
    });

    test('하루 종일이면 시각을 안 적는다 — 00:00 이라고 쓰면 안 된다', () {
      final plan = planReminders(
        schedules: [_schedule(title: '주말 목욕', kind: 'bath', atTime: null)],
        when: ScheduleReminderWhen.morningOf,
        now: _now,
      );

      expect(plan.single.body, '주말 목욕');
      expect(plan.single.body, isNot(contains('00:00')));
    });
  });

  group('담당 (#734)', () {
    test('담당이 있으면 담당자에게만 — 아빠 담당 병원은 엄마 폰에서 안 울린다', () {
      final plan = planReminders(
        schedules: [
          _schedule(id: 1, title: '아빠 담당 병원', assignee: _dad),
          _schedule(id: 2, title: '내 담당 미용', kind: 'groom', assignee: _me),
        ],
        when: ScheduleReminderWhen.morningOf,
        now: _now,
        myUserId: 5,
      );

      expect(plan.map((r) => r.scheduleId), [2],
          reason: '담당이라는 말이 알림에서도 뜻이 있어야 한다');
    });

    test('담당이 없으면 모두에게 — 누가 열어도 걸린다', () {
      for (final me in [5, 6]) {
        final plan = planReminders(
          schedules: [_schedule(id: 3, title: '가족 목욕', kind: 'bath')],
          when: ScheduleReminderWhen.morningOf,
          now: _now,
          myUserId: me,
        );
        expect(plan.map((r) => r.scheduleId), [3], reason: '$me 의 기기');
      }
    });

    test('누군지 모르면 담당 있는 일정은 안 건다 — 남의 것을 울리느니 비운다', () {
      final plan = planReminders(
        schedules: [
          _schedule(id: 1, title: '아빠 담당 병원', assignee: _dad),
          _schedule(id: 3, title: '가족 목욕', kind: 'bath'),
        ],
        when: ScheduleReminderWhen.morningOf,
        now: _now,
      );

      expect(plan.map((r) => r.scheduleId), [3]);
    });

    test('내 담당이면 본문 끝에 "내 담당" 이 붙는다 — 없는 일정에는 안 붙는다', () {
      final plan = planReminders(
        schedules: [
          _schedule(id: 2, title: '보리 병원', assignee: _me),
          _schedule(id: 3, title: '주말 목욕', kind: 'bath', atTime: null),
        ],
        when: ScheduleReminderWhen.morningOf,
        now: _now,
        myUserId: 5,
      );

      expect(plan.map((r) => r.body), ['보리 병원 · 10:30 · 내 담당', '주말 목욕']);
    });
  });
}

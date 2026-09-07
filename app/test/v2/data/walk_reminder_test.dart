// 저녁 산책 알림의 규칙 — 이슈 #341.
//
// ## 왜 시각을 인자로 받나
//
// "오늘 안 걸었으면 19시에 한 번" 은 시계에 걸려 있다. 안에서 `DateTime.now()` 를 불렀다면
// 이 테스트가 저녁 7시에만 다르게 돌거나, 가짜 시간을 흘려 넣어야 했다. **가짜 시간을 쓰면
// 그 테스트는 시계가 아니라 자기 자신을 잰다** — `nextReminderAt` 이 순수 함수인 이유다.
//
// ## 여기서 재는 것
//
//  1. 꺼져 있으면 안 건다 (완료 조건 4의 "설정에서 끄면 예약이 없다").
//  2. 오늘 걸었으면 오늘 것이 없다 (완료 조건 3의 "기록이 생기면 취소").
//  3. 시각이 지났으면 지금 울리지 않고 내일로 간다 — 지난 시각의 알림은 잔소리다.
//  4. 거는 쪽이 **언제나 먼저 지운다** — 두 번 울리는 것이 안 울리는 것보다 나쁘다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_reminder.dart';

const _on = WalkReminderSettings(enabled: true, hour: 19, minute: 0);

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 9, 7, hour, minute);

class _FakeSink implements WalkReminderSink {
  int cancels = 0;
  final List<({DateTime at, String title, String body})> scheduled = [];

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<void> scheduleAt(DateTime at, {required String title, required String body}) async =>
      scheduled.add((at: at, title: title, body: body));
}

void main() {
  group('언제 울릴까', () {
    test('꺼져 있으면 안 건다', () {
      expect(
        nextReminderAt(
          settings: const WalkReminderSettings(enabled: false, hour: 19),
          now: _at(10),
          todayWalkCount: 0,
        ),
        isNull,
      );
    });

    test('기본은 꺼짐이다 — 묻지 않고 알림을 보내지 않는다', () {
      expect(const WalkReminderSettings().enabled, isFalse);
      expect(WalkReminderSettings.defaultHour, 19);
    });

    test('오늘 아직 안 걸었고 시각 전이면 오늘 그 시각', () {
      expect(
        nextReminderAt(settings: _on, now: _at(10), todayWalkCount: 0),
        _at(19),
      );
    });

    test('오늘 이미 걸었으면 오늘 것이 없다 — 내일로 넘어간다', () {
      final at = nextReminderAt(settings: _on, now: _at(10), todayWalkCount: 1);

      expect(at, DateTime(2026, 9, 8, 19));
    });

    test('시각이 지났으면 지금 울리지 않고 내일이다 — 지난 시각의 알림은 잔소리다', () {
      final at = nextReminderAt(settings: _on, now: _at(21), todayWalkCount: 0);

      expect(at, DateTime(2026, 9, 8, 19));
    });

    test('그 시각 정각에는 이미 지난 것으로 본다 — 1초 차이로 두 번 걸리지 않게', () {
      expect(
        nextReminderAt(settings: _on, now: _at(19), todayWalkCount: 0),
        DateTime(2026, 9, 8, 19),
      );
    });

    test('분 단위 시각도 그대로 쓴다', () {
      final at = nextReminderAt(
        settings: const WalkReminderSettings(enabled: true, hour: 7, minute: 30),
        now: _at(6),
        todayWalkCount: 0,
      );

      expect(at, DateTime(2026, 9, 7, 7, 30));
    });
  });

  group('예약 걸기', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('켜고 안 걸은 날이면 오늘 그 시각에 걸린다 — 이름이 본문에 들어간다', () async {
      await const WalkReminderStore().save(_on);
      final sink = _FakeSink();

      final at = await WalkReminder(sink: sink).refresh(
        todayWalkCount: 0,
        dogName: 'Bori',
        now: _at(10),
      );

      expect(at, _at(19));
      expect(sink.scheduled.single.at, _at(19));
      expect(sink.scheduled.single.body, contains('Bori'));
      expect(sink.scheduled.single.body, isNot(contains('°C')),
          reason: '''
몇 시간 전에 예약되는 알림이다 — 아침에 잰 기온을 저녁에 보여 주면 그건 틀린 숫자다.
안전 지수는 앱을 열면 그 자리에서 다시 재서 보여 준다(WalkSafetyCard).''');
    });

    test('꺼져 있으면 지우기만 하고 아무것도 안 건다 (완료 조건 4)', () async {
      await const WalkReminderStore()
          .save(const WalkReminderSettings(enabled: false, hour: 19));
      final sink = _FakeSink();

      final at = await WalkReminder(sink: sink).refresh(todayWalkCount: 0, now: _at(10));

      expect(at, isNull);
      expect(sink.cancels, 1, reason: '끄면 이미 걸려 있던 것도 사라져야 한다');
      expect(sink.scheduled, isEmpty);
    });

    test('언제나 먼저 지운다 — 두 번 울리는 것이 안 울리는 것보다 나쁘다', () async {
      await const WalkReminderStore().save(_on);
      final sink = _FakeSink();

      await WalkReminder(sink: sink).refresh(todayWalkCount: 0, now: _at(10));
      await WalkReminder(sink: sink).refresh(todayWalkCount: 0, now: _at(11));

      expect(sink.cancels, 2);
      expect(sink.scheduled, hasLength(2));
    });

    test('산책을 저장한 뒤 부르면 오늘 것이 사라지고 내일로 간다 (완료 조건 3)', () async {
      await const WalkReminderStore().save(_on);
      final sink = _FakeSink();

      final at = await WalkReminder(sink: sink).refresh(todayWalkCount: 1, now: _at(10));

      expect(at, DateTime(2026, 9, 8, 19));
    });

    test('이름을 모르면 이름 없이 말한다', () async {
      await const WalkReminderStore().save(_on);
      final sink = _FakeSink();

      await WalkReminder(sink: sink).refresh(todayWalkCount: 0, now: _at(10));

      expect(sink.scheduled.single.body, '오늘 아직 산책 기록이 없어요');
    });
  });

  group('설정 저장', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('적은 대로 읽힌다', () async {
      const store = WalkReminderStore();
      const settings = WalkReminderSettings(enabled: true, hour: 7, minute: 30);

      await store.save(settings);

      expect(await store.read(), settings);
    });

    test('아무것도 없으면 꺼진 기본값이다', () async {
      expect(await const WalkReminderStore().read(), const WalkReminderSettings());
    });

    test('말이 안 되는 시각은 기본값으로 돌아간다', () {
      expect(WalkReminderSettings.tryParse({'enabled': true, 'hour': 24}), isNull);
      expect(WalkReminderSettings.tryParse({'enabled': true, 'hour': 9, 'minute': 60}), isNull);
    });

    test('시각 문구는 오전·오후로 적는다', () {
      expect(const WalkReminderSettings(hour: 19).timeLabel, '오후 7:00');
      expect(const WalkReminderSettings(hour: 7, minute: 30).timeLabel, '오전 7:30');
      expect(const WalkReminderSettings(hour: 0, minute: 5).timeLabel, '오전 12:05');
      expect(const WalkReminderSettings(hour: 12).timeLabel, '오후 12:00');
    });
  });
}

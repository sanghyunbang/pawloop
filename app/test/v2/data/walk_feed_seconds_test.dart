// 주간 합계가 산책마다 초를 버리던 것 — 이슈 #537.
//
// ## 무엇이 있었나
//
// 대기 중인 초안을 주간 분에 얹을 때 **초안마다** `~/ 60` 했다.
//
// ```dart
// week[index] += draft.durationS ~/ 60;   // 30초 → 0
// ```
//
// 30초짜리 셋을 걸으면 90초인데 주간 목표에는 `0분` 이 쌓였다. 서버는 같은 이유로 초로 더한
// 뒤 나눈다(#341, `WalkService` — "산책 다섯 번이 5분이 아니라 0분이 된다"). 앱의 초안 쪽만
// 그 규칙 밖에 있었다.
//
// 오늘 요약(`today`)도 분으로 잘라서 줬다. 초로 주고, 내리는 것은 그리는 자리의 몫이다.
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';

WalkDraft _draft(DateTime at, int durationS) => WalkDraft(
      clientWalkId: 'ck-${at.millisecondsSinceEpoch}-$durationS',
      startedAt: at,
      endedAt: at.add(Duration(seconds: durationS)),
      distanceM: 300,
      durationS: durationS,
      path: const [],
    );

WalkFeedData _feed(List<WalkDraft> pending) => WalkFeedData(
      walks: const [],
      pending: pending,
      stats: ServerWalkStats.empty,
      offline: false,
    );

void main() {
  // **이번 주** 월요일. `weekMinutesWithPending` 은 안에서 `DateTime.now()` 로 주를 잡으므로,
  // 날짜를 못박으면 다음 주에 이 테스트가 조용히 빨개진다.
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1))
      .add(const Duration(hours: 8));

  group('주간 합계', () {
    test('같은 날 30초짜리 셋은 1분이다 — 예전에는 0분이었다 (#537)', () {
      final week = _feed([
        _draft(monday, 30),
        _draft(monday.add(const Duration(hours: 1)), 30),
        _draft(monday.add(const Duration(hours: 2)), 30),
      ]).weekMinutesWithPending;

      expect(week[0], 1, reason: '90초를 초안마다 자르면 0분이 된다');
    });

    test('날이 다르면 각자 내린다 — 월 30초 · 화 30초는 둘 다 0분', () {
      final week = _feed([
        _draft(monday, 30),
        _draft(monday.add(const Duration(days: 1)), 30),
      ]).weekMinutesWithPending;

      expect(week[0], 0);
      expect(week[1], 0);
      expect(week.length, 7);
    });

    test('1분이 넘는 것은 지금 그대로', () {
      final week = _feed([_draft(monday, 720)]).weekMinutesWithPending;

      expect(week[0], 12);
    });

    test('이번 주 밖의 초안은 안 센다', () {
      final week = _feed([_draft(monday.subtract(const Duration(days: 3)), 600)])
          .weekMinutesWithPending;

      expect(week, everyElement(0));
    });
  });

  group('오늘 요약', () {
    test('초로 준다 — 분으로 내리는 것은 그리는 자리의 몫이다', () {
      final today = _feed([_draft(DateTime.now(), 44)]).today;

      expect(today.durationS, 44);
      expect(today.count, 1);
    });

    test('여러 번 걸으면 초를 더한다', () {
      final at = DateTime.now();
      final today = _feed([_draft(at, 44), _draft(at.add(const Duration(seconds: 1)), 40)]).today;

      expect(today.durationS, 84, reason: '84초는 1분이다 — 각각 잘랐으면 0분이다');
    });
  });
}

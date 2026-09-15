// 세션이 끝나면 기기에 무엇이 남고 무엇이 사라지는가 — 이슈 #513.
//
// 이 결함은 **다음 사람 화면에서만** 드러난다. 앞사람 동네로 지도가 열리고, 앞사람의
// 전송 대기 산책이 뒷사람 토큰으로 나가고, 앞사람의 일정 제목이 잠금화면에 뜬다.
// 그래서 여기서 재는 것은 "지웠는가" 만이 아니라 **"안 지울 것을 지켰는가"** 이기도 하다.
// 위치 이용중지(`location_paused_v1`)를 함께 지우면 껐던 수집이 도로 켜진다.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/neighborhood_store.dart';
import 'package:heat_trip_flutter/v2/data/session_traces.dart';
import 'package:heat_trip_flutter/v2/data/walk_goal_store.dart';
import 'package:heat_trip_flutter/v2/data/walk_in_progress.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_reminder.dart';
import 'package:heat_trip_flutter/v2/data/walk_safety_repository.dart';
import 'package:heat_trip_flutter/v2/data/weekly_report_reminder.dart';
import 'package:heat_trip_flutter/v2/domain/schedule_reminder.dart';

/// 알림을 지웠는지만 센다.
class _FakeNotifications implements SessionNotificationSink {
  int cancelled = 0;

  @override
  Future<void> cancelEverything() async => cancelled++;
}

/// 세션의 것 — 하나씩 이름으로 적는다. `sessionScopedKeys` 를 돌면 목록에서 한 줄을
/// 빼는 변형에 이 테스트가 **함께 눈을 감는다**(세우지도 않고 재지도 않게 된다).
/// 그 변형은 분류 게이트가 따로 잡지만, 여기서도 잡히는 편이 낫다.
const Map<String, String> _sessionValues = <String, String>{
  NeighborhoodStore.key: '앞사람 동네',
  WalkOutbox.pendingKey: '앞사람의 전송 대기 산책',
  WalkOutbox.rejectedKey: '앞사람의 거절된 산책',
  WalkInProgressStore.key: '앞사람의 끊긴 산책',
  WalkReminderStore.key: '앞사람의 산책 알림 설정',
  WeeklyReportReminderStore.key: '앞사람의 주간 정리 설정',
  ScheduleReminderStore.key: '앞사람의 일정 알림 설정',
};

/// 기기의 것 — 세션이 끝나도 남아야 한다. 값은 아무거나.
const Map<String, Object> _deviceValues = <String, Object>{
  'intro_seen_v1': true,
  'location_paused_v1': true,
  'location_priming_asked_v1': true,
  'place_catalog_etag_v1': 'W/"abc"',
  'place_catalog_checked_at_v1': 1,
};

void main() {
  late _FakeNotifications notifications;

  setUp(() {
    notifications = _FakeNotifications();
    sessionNotifications = () => notifications;
    SharedPreferences.setMockInitialValues(<String, Object>{
      ..._sessionValues,
      'v2.walk_goal': '앞사람의 기본 목표',
      'v2.walk_goal.7': '앞사람 아이의 목표',
      ..._deviceValues,
    });
  });

  tearDown(() {
    sessionNotifications = null;
    WalkSafetyStore.clear();
  });

  test('세션 것은 지우고 기기 것은 남긴다', () async {
    await clearSessionTraces();

    final prefs = await SharedPreferences.getInstance();
    for (final key in _sessionValues.keys) {
      expect(prefs.getKeys(), isNot(contains(key)),
          reason: '$key 가 남으면 다음 사람이 앞사람의 것을 본다');
    }
    for (final entry in _deviceValues.entries) {
      expect(prefs.get(entry.key), entry.value,
          reason: '${entry.key} 는 기기의 것이다 — 지우면 안 된다');
    }
  });

  test('아이마다 생긴 목표 키까지 훑어서 지운다 — 개수를 모르는 것은 접두사로 찾는다', () async {
    await clearSessionTraces();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith(WalkGoalStore.prefix)), isEmpty);
  });

  test('예약된 알림을 전부 지운다 — 앞사람의 일정 제목이 잠금화면에 뜨면 안 된다', () async {
    await clearSessionTraces();

    expect(notifications.cancelled, 1);
  });

  test('알림 지우개가 안 꽂혀 있어도 나머지는 지운다 — 로그아웃은 여기서 멈추면 안 된다', () async {
    sessionNotifications = null;

    await clearSessionTraces();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where(_sessionValues.containsKey), isEmpty);
  });

  test('안전 지수 캐시가 비고, 그 값을 듣는 화면이 다시 읽는다', () async {
    WalkSafetyStore.fetchedAt = DateTime(2026, 9, 15, 12);
    final before = <int>[kNeighborhoodRev.value, kWalkReminderRev.value];

    await clearSessionTraces();

    expect(WalkSafetyStore.isFresh(DateTime(2026, 9, 15, 12, 1)), isFalse,
        reason: '앞사람 위치로 낸 판정이 다음 사람 홈 카드에 남으면 안 된다');
    expect(kNeighborhoodRev.value, greaterThan(before[0]));
    expect(kWalkReminderRev.value, greaterThan(before[1]));
  });
}

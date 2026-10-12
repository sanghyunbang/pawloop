// lib/v2/data/session_traces.dart
//
// 세션이 끝나면 기기에서 지울 것 — 이슈 #513.
//
// ## 로그아웃은 토큰만 지우면 끝나는 일이 아니다
//
// 지우지 않으면 다음 사람 화면에서 이렇게 드러난다.
//
//  - 앞사람 **동네**로 지도와 피드가 열린다.
//  - 앞사람의 **전송 대기 산책**이 뒷사람 토큰으로 서버에 나간다.
//  - 끊긴 산책 스냅숏이 남아 **남의 산책**을 이어 걷겠냐고 묻는다.
//  - 예약된 알림이 앞사람의 **일정 제목과 아이 이름**을 잠금화면에 띄운다.
//  - 앞사람 위치로 낸 안전 지수가 홈 카드에 남는다.
//
// 화면마다 하나씩 지우면 **빠뜨리는 날**이 오고, 빠진 것은 다음 사람 화면에서만
// 드러난다. 그래서 "세션이 끝났다" 를 아는 한 곳이 여기를 부른다 —
// 로그아웃 · 탈퇴 · 세션 만료 셋이 모두 `AuthState` 의 같은 함수를 지난다.
//
// ## 키 문자열을 여기 베껴 적지 않는다
//
// 지우는 키는 전부 **저장소가 든 상수**다. 여기에 문자열을 베끼면 저장소가 키를
// 바꾸는 날 이 목록만 조용히 낡는다 — 그리고 그 사실은 아무 데도 안 나타난다.
//
// ## 무엇을 **안** 지우는가 — 그것도 여기 적는다
//
// | 남기는 것 | 왜 |
// |---|---|
// | `intro_seen_v1` | 소개는 기기에 한 번이다. 다음 사람이 다시 볼 이유가 없다 |
// | `location_paused_v1` | **끈 것을 켜면 안 된다.** 지우면 위치 수집이 도로 켜진다(위치정보법 제24조) |
// | `location_priming_asked_v1` | "OS 권한을 한 번 물었다" 는 기기의 사실이다 |
// | `place_catalog_*` | 공개 카탈로그 캐시라 개인의 것이 아니다 |
//
// 계정 id 가 붙는 키(`account_consent_v2_<id>` · `chat_terms_agreed_v1_<id>`)는 섞이지
// 않는다 — 동의는 그래도 `AuthState.clearLocalSession` 이 지운다(#180).
//
// 반려동물은 여기가 아니라 `PetLoader` 가 지운다. 거긴 불러오기와 짝이고, 기기에
// 남는 것이 없다(메모리 `kMyPets` 뿐).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/schedule_reminder.dart';
import 'avatar_border_store.dart';
import 'blocked_authors.dart';
import 'neighborhood_store.dart';
import 'walk_goal_store.dart';
import 'walk_in_progress.dart';
import 'walk_outbox.dart';
import 'walk_reminder.dart';
import 'walk_safety_repository.dart';
import 'weekly_report_reminder.dart';

/// 예약된 알림을 지우는 자리.
abstract interface class SessionNotificationSink {
  /// 이 기기에 걸린 우리 알림 **전부** — 산책 · 주간 정리 · 일정 셋 다.
  Future<void> cancelEverything();
}

/// 알림 지우개를 만드는 법. **`main()` 이 꽂는다.**
///
/// 이 파일이 `flutter_local_notifications` 를 직접 import 하면 순수 테스트가 채널
/// 없이 던진다 — `ScheduleReminderSink` 가 순수 파일에 사는 것과 같은 선이다.
/// 비어 있으면 알림만 건너뛴다(테스트).
SessionNotificationSink Function()? sessionNotifications;

/// 세션이 끝나면 지우는 키들. 각 저장소가 자기 키를 든다.
const List<String> sessionScopedKeys = <String>[
  AvatarBorderStore.key,
  NeighborhoodStore.key,
  WalkOutbox.pendingKey,
  WalkOutbox.rejectedKey,
  WalkInProgressStore.key,
  WalkReminderStore.key,
  WeeklyReportReminderStore.key,
  ScheduleReminderStore.key,
];

/// 아이마다 하나씩 생기는 키의 앞머리. 개수를 모르므로 훑어서 지운다.
const List<String> sessionScopedKeyPrefixes = <String>[
  WalkGoalStore.prefix,
];

/// 세션이 끝났다. 기기에 남은 앞사람의 흔적을 지운다.
///
/// **하나가 실패해도 나머지는 지운다.** 로그아웃은 여기서 멈추면 안 되는 일이다 —
/// 토큰은 이미 지워졌고, 사용자는 이미 나갔다. 실패는 디버그 로그로만 남긴다.
Future<void> clearSessionTraces() async {
  await _swallow('prefs', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in sessionScopedKeys) {
      await prefs.remove(key);
    }
    for (final key in prefs.getKeys().toList()) {
      if (sessionScopedKeyPrefixes.any((p) => key == p || key.startsWith('$p.'))) {
        await prefs.remove(key);
      }
    }
  });

  await _swallow('notifications', () async {
    final sink = sessionNotifications?.call();
    if (sink == null) return;
    await sink.cancelEverything();
  });

  // 메모리에 있는 것. 다음 사람이 들어오기 전에 화면에서도 사라져야 한다.
  WalkSafetyStore.clear();
  // 이 세션에서 차단한 사람 — 다음 사람에게 앞사람의 차단이 적용되면 그 사람 화면에서 글이 사라진다.
  BlockedAuthors.clear();

  // 이 값들을 듣는 화면이 아직 떠 있을 수 있다 — 다시 읽게 해서 기본값으로 돌린다.
  kNeighborhoodRev.value++;
  kWalkReminderRev.value++;
  kWeeklyReportReminderRev.value++;
  kScheduleReminderRev.value++;
  kWalkGoalRev.value++;
}

Future<void> _swallow(String what, Future<void> Function() run) async {
  try {
    await run();
  } catch (e) {
    if (kDebugMode) debugPrint('[SessionTraces] $what 을(를) 못 지웠다: ${e.runtimeType}');
  }
}

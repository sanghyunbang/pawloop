// lib/v2/data/walk_reminder.dart
//
// 저녁에 한 번, 오늘 안 나갔으면 — 이슈 #341.
//
// ## 푸시가 아니다
//
// 서버가 보내는 알림(#83, FCM)과 **아무 관계가 없다.** 기기 안에서 예약하고 기기가 띄운다 —
// 서버는 이 사람이 오늘 걸었는지도, 알림을 켰는지도 모른다. 그래서 이 기능에는 토큰도
// 동의도 새로 필요하지 않다.
//
// ## 규칙이 순수 함수인 이유
//
// "언제 울릴까" 는 시계·저장소·플러그인이 얽히는 자리다. 그것을 [nextReminderAt] 하나로
// 떼어 두면 **시각을 인자로 받아** 잴 수 있다. 가짜 시간을 흘려 재는 테스트는 시계가 아니라
// 자기 자신을 재게 된다 — 그 함정을 이 저장소가 이미 한 번 밟았다.
//
// ## 정확 알람을 안 쓴다
//
// 안드로이드 12+ 의 `SCHEDULE_EXACT_ALARM` 은 사용자에게 한 번 더 묻는 권한이다. 산책
// 알림이 1분 어긋나는 것과 권한 대화상자를 하나 더 띄우는 것 중에서 전자를 고른다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 저녁 알림 설정 — 켬/끔과 시각.
class WalkReminderSettings {
  const WalkReminderSettings({
    this.enabled = defaultEnabled,
    this.hour = defaultHour,
    this.minute = 0,
  });

  /// **기본은 꺼짐이다.** 묻지 않고 알림을 보내는 앱이 되면 안 된다 — 켜는 것은 사용자가
  /// 설정에서 하는 일이고, 그 자리에 무엇을 보낼지 한 줄로 적어 둔다.
  static const bool defaultEnabled = false;

  /// 이슈가 정한 기본 시각. 저녁 산책을 나갈 수 있는 마지막 무렵이다.
  static const int defaultHour = 19;

  final bool enabled;
  final int hour;
  final int minute;

  WalkReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      WalkReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  /// "오후 7:00".
  String get timeLabel {
    final ampm = hour < 12 ? '오전' : '오후';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$ampm $h12:${minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {'enabled': enabled, 'hour': hour, 'minute': minute};

  static WalkReminderSettings? tryParse(Object? json) {
    if (json is! Map) return null;
    final hour = (json['hour'] as num?)?.toInt() ?? defaultHour;
    final minute = (json['minute'] as num?)?.toInt() ?? 0;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return WalkReminderSettings(
      enabled: json['enabled'] == true,
      hour: hour,
      minute: minute,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WalkReminderSettings &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);
}

/// 설정이 바뀐 횟수. 설정 화면이 저장하면 올라가고, 예약을 다시 거는 쪽이 그것을 본다.
final ValueNotifier<int> kWalkReminderRev = ValueNotifier<int>(0);

class WalkReminderStore {
  const WalkReminderStore();

  /// 설정이 남는 자리. **세션 것이다** — 로그아웃하면 지운다(#513).
  static const String key = 'v2.walk_reminder';

  Future<WalkReminderSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const WalkReminderSettings();
    try {
      return WalkReminderSettings.tryParse(jsonDecode(raw)) ??
          const WalkReminderSettings();
    } on FormatException {
      return const WalkReminderSettings();
    }
  }

  Future<void> save(WalkReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(settings.toJson()));
    kWalkReminderRev.value++;
  }
}

/// 다음에 울릴 시각. **울릴 필요가 없으면 `null`** 이고, 그때 부르는 쪽은 예약을 지운다.
///
/// 규칙 넷이 여기 다 있다.
///
///  1. 꺼져 있으면 안 울린다.
///  2. **오늘 이미 걸었으면 오늘 것은 없다** — 완료 조건 4 의 "기록하면 그날 것은 취소".
///  3. 아직 그 시각 전이면 오늘 그 시각.
///  4. 이미 지났으면 **내일** 그 시각. 지난 시각에 지금 울리면 그건 알림이 아니라 잔소리다.
///
/// [todayWalkCount] 는 오늘 걸은 횟수다(전송 대기 포함 — 사용자는 이미 걸었다).
DateTime? nextReminderAt({
  required WalkReminderSettings settings,
  required DateTime now,
  required int todayWalkCount,
}) {
  if (!settings.enabled) return null;

  final todayAt = DateTime(now.year, now.month, now.day, settings.hour, settings.minute);

  if (todayWalkCount == 0 && now.isBefore(todayAt)) return todayAt;

  // 오늘은 지났거나 이미 걸었다 — 내일 같은 시각으로 건다. 내일 아침에 걸으면
  // 그때 다시 이 함수가 돌아 예약이 사라진다.
  return todayAt.add(const Duration(days: 1));
}

/// 알림을 실제로 거는 자리. 테스트는 이것을 가짜로 갈아끼운다.
abstract class WalkReminderSink {
  /// 예약을 전부 지운다.
  Future<void> cancelAll();

  /// [at] 에 한 번 울리게 건다.
  Future<void> scheduleAt(DateTime at, {required String title, required String body});
}

/// 예약을 맞춰 두는 자리. 화면들은 [refresh] 하나만 부른다.
///
/// **부를 때마다 지우고 다시 건다.** 상태를 들고 있으면 "지금 걸려 있는 것이 무엇인가" 를
/// 두 곳이 알게 되고, 그 둘이 어긋나는 날 알림이 두 번 울리거나 한 번도 안 울린다.
class WalkReminder {
  const WalkReminder({required this.sink, this.store = const WalkReminderStore()});

  final WalkReminderSink sink;
  final WalkReminderStore store;

  /// 알림 제목·본문. **날씨를 안 적는다.**
  ///
  /// 이슈는 "지금 22°C, 나가기 좋아요" 를 함께 적자고 했는데, 이 알림은 **몇 시간 전에**
  /// 예약된다 — 아침 10시에 잰 기온을 저녁 7시에 보여 주면 그건 틀린 숫자다. 안전 지수는
  /// 앱을 열면 그 자리에서 다시 재서 보여 준다(`WalkSafetyCard`).
  static const title = '산책 다녀올까요?';

  static String bodyFor(String? dogName) =>
      dogName == null || dogName.isEmpty
          ? '오늘 아직 산책 기록이 없어요'
          : '$dogName 오늘 아직 산책 기록이 없어요';

  /// 설정과 오늘 기록을 보고 예약을 맞춘다.
  Future<DateTime?> refresh({
    required int todayWalkCount,
    String? dogName,
    DateTime? now,
  }) async {
    final settings = await store.read();
    final at = nextReminderAt(
      settings: settings,
      now: now ?? DateTime.now(),
      todayWalkCount: todayWalkCount,
    );

    await sink.cancelAll();
    if (at == null) return null;

    await sink.scheduleAt(at, title: title, body: bodyFor(dogName));
    return at;
  }
}

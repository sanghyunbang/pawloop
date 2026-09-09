// lib/v2/data/local_notification_sink.dart
//
// [WalkReminderSink] 의 진짜 구현 — `flutter_local_notifications` 를 부르는 유일한 자리.
//
// ## 왜 파일을 나눴나
//
// 규칙(언제 울릴까)은 `walk_reminder.dart` 에 있고 순수 함수다. 여기는 **플러그인을 아는
// 유일한 파일**이라 위젯 테스트가 이것을 import 하지 않는다 — 플러그인은 테스트 바인딩에서
// 채널이 없어 던진다.
//
// ## 시간대
//
// `zonedSchedule` 은 `TZDateTime` 을 받는다. 기기의 시간대를 읽어 그 지역으로 만든다 —
// UTC 로 걸면 한국에서 저녁 7시 알림이 새벽 4시에 울린다. 에뮬레이터에서 실제로 시계가
// UTC 인 채로 산책 안전 지수가 9시간 어긋난 적이 있다(#336 실측).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/schedule_reminder.dart';
import 'walk_reminder.dart';

class LocalNotificationSink implements WalkReminderSink, ScheduleReminderSink {
  LocalNotificationSink({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  /// 알림 하나만 쓴다 — 저녁 산책 알림은 언제나 최대 한 건이다(완료 조건 4).
  static const int notificationId = 341;

  /// 지난번에 건 일정 알림의 id 들. 다음 번에 이것부터 거둔다.
  ///
  /// **메모리에만 둔다.** 앱을 껐다 켜면 비어 있고, 그러면 옛 예약이 남는다 — 그래도 그
  /// 예약은 자기 시각에 한 번 울리고 사라지므로 잘못된 알림이 되지 않는다. 저장소에 두면
  /// 그 목록이 실제 예약과 갈리는 날이 오고, 그건 고치기가 더 어렵다.
  final Set<int> _scheduleIds = <int>{};

  static const _scheduleChannelId = 'schedule_reminder';
  static const _scheduleChannelName = '일정 알림';
  static const _scheduleChannelDescription = '적어 둔 일정을 전날 저녁이나 당일 아침에 알려 줍니다.';

  static const _channelId = 'walk_reminder';
  static const _channelName = '산책 알림';
  static const _channelDescription = '오늘 산책 기록이 없을 때 저녁에 한 번 알려 줍니다.';

  Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // 기기 시간대 이름을 못 읽는 환경이 있다(에뮬레이터·일부 커스텀 롬). 그때는 서울로
    // 둔다 — 이 앱의 사용자는 한국에 있고, UTC 로 두면 저녁 알림이 새벽에 울린다.
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }

    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // 알림을 켜는 순간에만 묻는다 — 앱을 처음 여는 사람에게 권한부터 묻지 않는다.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  /// 알림 권한. **켜는 순간에만** 묻는다 — 설정 화면의 스위치가 이것을 부른다.
  Future<bool> requestPermission() async {
    await _ensureReady();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> cancelAll() async {
    await _ensureReady();
    await _plugin.cancel(notificationId);
  }

  @override
  Future<void> replaceAll(List<ScheduleReminder> reminders) async {
    await _ensureReady();
    for (final id in _scheduleIds) {
      await _plugin.cancel(id);
    }
    _scheduleIds
      ..clear()
      ..addAll(reminders.map((r) => r.id));

    for (final r in reminders) {
      await _plugin.zonedSchedule(
        r.id,
        r.title,
        r.body,
        tz.TZDateTime.from(r.at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _scheduleChannelId,
            _scheduleChannelName,
            channelDescription: _scheduleChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    if (kDebugMode) {
      debugPrint('[ScheduleReminder] 예약 ${reminders.length}건');
    }
  }

  @override
  Future<void> scheduleAt(DateTime at, {required String title, required String body}) async {
    await _ensureReady();
    await _plugin.zonedSchedule(
      notificationId,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // 정확 알람 권한(안드로이드 12+)을 안 쓴다. 1분 어긋나도 되는 알림이고,
      // 그 권한은 사용자에게 한 번 더 묻는다.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    if (kDebugMode) {
      debugPrint('[WalkReminder] 예약 $at');
    }
  }
}

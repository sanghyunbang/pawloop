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
import 'notification_route.dart';
import 'push_route.dart';
import 'session_traces.dart';
import 'walk_reminder.dart';
import 'weekly_report_reminder.dart';

class LocalNotificationSink
    implements WalkReminderSink, ScheduleReminderSink, WeeklyReportReminderSink, SessionNotificationSink {
  LocalNotificationSink({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  /// 알림 하나만 쓴다 — 저녁 산책 알림은 언제나 최대 한 건이다(완료 조건 4).
  static const int notificationId = 341;

  /// 일요일 저녁 주간 정리(#486 후속) — 산책 알림(341)·일정 알림(일정 id)과 겹치지 않는 번호.
  static const int weeklyReportNotificationId = 486;
  static const _weeklyChannelId = 'weekly_report';
  static const _weeklyChannelName = '주간 정리 알림';
  static const _weeklyChannelDescription = '일요일 저녁에 이번 주 산책 요약을 보러 오라고 한 번 알려 줍니다.';

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

  /// 서버 푸시(#83)의 채널. **매니페스트의 FCM 기본 채널 id 와 같아야 한다** — 뒤에서 온 푸시는 FCM 이
  /// 직접 띄우는데, 그때 이 id 의 채널이 없으면 이름 없는 채널로 가서 설정에 "기타" 로 보인다.
  static const pushChannelId = 'push';
  static const _pushChannelName = '가족 알림';
  static const _pushChannelDescription = '가족이 일정을 맡기거나 채팅을 보내면 알려 줍니다.';

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

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // 알림을 켜는 순간에만 묻는다 — 앱을 처음 여는 사람에게 권한부터 묻지 않는다.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // 앱이 떠 있는 동안 누른 알림. 어디로 갈지는 payload 가 말한다.
      onDidReceiveNotificationResponse: (response) => offerFromNotification(response.payload),
    );

    // **꺼져 있던 앱이 알림으로 떴을 때**는 위 콜백이 오지 않는다 — 그때는 플러그인이 들고 있던
    // 것을 여기서 한 번 읽는다. 홈이 떠서 가져갈 때까지 [NotificationRouteInbox] 가 들고 있는다.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      offerFromNotification(launch?.notificationResponse?.payload);
    }
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

  /// 푸시 채널을 만들어 둔다 — 앱이 시작할 때 한 번(`FirebasePush.start`). 이미 있으면 그대로다.
  Future<void> ensurePushChannel() async {
    await _ensureReady();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      pushChannelId,
      _pushChannelName,
      description: _pushChannelDescription,
      importance: Importance.high,
    ));
  }

  /// 앞에 떠 있을 때 온 푸시를 띄운다(#83). 누르면 payload 가 말하는 곳으로 간다 — 위
  /// `onDidReceiveNotificationResponse` 가 기기 알림과 같은 길로 보낸다.
  Future<void> showPush(ForegroundNotice notice) async {
    await _ensureReady();
    await _plugin.show(
      notice.id,
      notice.title,
      notice.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          pushChannelId,
          _pushChannelName,
          channelDescription: _pushChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: notice.payload,
    );
  }

  @override
  Future<void> cancelAll() async {
    await _ensureReady();
    await _plugin.cancel(notificationId);
  }

  /// 세션이 끝났다 — 이 기기에 걸린 우리 알림을 <b>전부</b> 지운다(#513).
  ///
  /// [cancelAll] 은 이름과 달리 산책 알림 하나만 지운다(그쪽은 `WalkReminderSink`
  /// 의 규약이다). 일정 알림은 id 가 여럿이고 주간 정리는 또 다른 id 라, 하나씩
  /// 지우면 빠뜨린다. 여기서는 플러그인에게 통째로 맡긴다.
  @override
  Future<void> cancelEverything() async {
    await _ensureReady();
    await _plugin.cancelAll();
  }

  @override
  Future<void> cancelWeeklyReport() async {
    await _ensureReady();
    await _plugin.cancel(weeklyReportNotificationId);
  }

  @override
  Future<void> scheduleWeeklyReportAt(DateTime at, {required String title, required String body}) async {
    await _ensureReady();
    await _plugin.zonedSchedule(
      weeklyReportNotificationId,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _weeklyChannelId,
          _weeklyChannelName,
          channelDescription: _weeklyChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // 산책 알림과 같은 이유로 정확 알람을 안 쓴다 — 몇 분 어긋나도 되는 알림이다.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: weeklyReportPayload,
    );
    if (kDebugMode) {
      debugPrint('[WeeklyReportReminder] 예약 $at');
    }
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

    // 무엇을 싣는가는 여기서 정하지 않는다 — `scheduleNotificationsFor` 가 정하고 테스트가 잰다.
    for (final n in scheduleNotificationsFor(reminders)) {
      await _plugin.zonedSchedule(
        n.id,
        n.title,
        n.body,
        tz.TZDateTime.from(n.at, tz.local),
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
        // 종류만이 아니라 **그 일정**을 싣는다 — 누르면 그 날이 열린다(#420 후속).
        payload: n.payload,
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
      payload: walkReminderPayload,
    );
    if (kDebugMode) {
      debugPrint('[WalkReminder] 예약 $at');
    }
  }
}

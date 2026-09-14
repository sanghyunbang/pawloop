// lib/v2/widgets/weekly_report_reminder_sync.dart
//
// 일요일 저녁 알림 예약을 걸어 두는 조각 — 아무것도 안 그린다(`walk_reminder_sync.dart` 와 같은 모양).
//
// 다시 걸어야 하는 순간은 둘이다 — 앱을 열 때(홈이 뜬다), 설정을 바꿨을 때. 주간 알림은 화면 자료에
// 기대지 않으므로 한 번 걸면 같은 값으로 다시 걸지 않는다 — 알람을 계속 갈아 끼우면 로그가 그것으로 찬다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_notification_sink.dart';
import '../data/weekly_report_reminder.dart';

class WeeklyReportReminderSync extends StatefulWidget {
  const WeeklyReportReminderSync({super.key, required this.guest, this.sink, this.now});

  /// 게스트에게는 걸 것이 없다 — 볼 통계가 없다.
  final bool guest;
  final WeeklyReportReminderSink? sink;
  final DateTime? now;

  @override
  State<WeeklyReportReminderSync> createState() => _WeeklyReportReminderSyncState();
}

class _WeeklyReportReminderSyncState extends State<WeeklyReportReminderSync> {
  LocalNotificationSink? _real;
  bool _synced = false;
  bool _running = false;

  WeeklyReportReminderSink get _sink => widget.sink ?? (_real ??= LocalNotificationSink());

  @override
  void initState() {
    super.initState();
    _sync();
    kWeeklyReportReminderRev.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    kWeeklyReportReminderRev.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(WeeklyReportReminderSync old) {
    super.didUpdateWidget(old);
    if (old.guest != widget.guest) _sync();
  }

  void _onSettingsChanged() {
    _synced = false;
    _sync();
  }

  Future<void> _sync() async {
    if (widget.guest || _running || _synced) return;
    _running = true;
    try {
      await WeeklyReportReminder(sink: _sink).refresh(now: widget.now);
      _synced = true;
    } catch (e) {
      // **홈은 살아 있어야 한다.** 알림은 곁다리다 — 플러그인이 없는 환경(웹 · 테스트 바인딩)에서
      // 예약이 던져도 여기서 멈춘다.
      if (kDebugMode) {
        debugPrint('[WeeklyReportReminder] 예약 실패: $e');
      }
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

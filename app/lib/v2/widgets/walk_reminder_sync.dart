// lib/v2/widgets/walk_reminder_sync.dart
//
// 저녁 알림 예약을 화면의 자료에 맞춰 두는 조각 — 이슈 #341.
//
// ## 왜 위젯인가 (아무것도 안 그리는데)
//
// 예약을 다시 걸어야 하는 순간이 셋이다 — 앱을 열 때, 산책을 저장했을 때, 설정을 바꿨을 때.
// 앞의 둘은 **홈이 산책 자료를 다시 읽는 순간과 같다.** 그 자료를 이미 들고 있는 자리에
// 붙이면 서버를 한 번 더 부르지 않아도 된다.
//
// 그리는 것이 없으므로 화면의 모양에는 영향이 없다 — 하는 일이 하나뿐인 조각이다.
//
// ## 같은 값으로 다시 안 건다
//
// 홈은 자주 다시 그려진다. 그릴 때마다 예약을 지우고 다시 걸면 안드로이드의 알람이
// 계속 갈아 끼워지고, 로그가 그것으로 찬다. 그래서 **마지막으로 건 시각**을 들고 있다가
// 달라질 때만 건다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_notification_sink.dart';
import '../data/walk_feed.dart';
import '../data/walk_reminder.dart';

class WalkReminderSync extends StatefulWidget {
  const WalkReminderSync({
    super.key,
    required this.data,
    this.dogName,
    this.sink,
    this.now,
  });

  final WalkFeedData data;
  final String? dogName;

  /// 테스트가 가짜를 꽂는 자리. `null` 이면 진짜 플러그인이다.
  final WalkReminderSink? sink;

  final DateTime? now;

  @override
  State<WalkReminderSync> createState() => _WalkReminderSyncState();
}

class _WalkReminderSyncState extends State<WalkReminderSync> {
  LocalNotificationSink? _real;
  DateTime? _scheduledAt;
  int? _lastCount;
  bool _running = false;

  WalkReminderSink get _sink => widget.sink ?? (_real ??= LocalNotificationSink());

  @override
  void initState() {
    super.initState();
    _sync();
    kWalkReminderRev.addListener(_sync);
  }

  @override
  void dispose() {
    kWalkReminderRev.removeListener(_sync);
    super.dispose();
  }

  @override
  void didUpdateWidget(WalkReminderSync old) {
    super.didUpdateWidget(old);
    if (old.data.today.count != widget.data.today.count) _sync();
  }

  Future<void> _sync() async {
    // 게스트에게는 걸 것이 없다 — 기록이 없는 것이 아니라 **읽지 않은** 상태다.
    if (widget.data.guest || _running) return;
    final count = widget.data.today.count;
    if (_lastCount == count && _scheduledAt != null) return;
    _running = true;
    try {
      final at = await WalkReminder(sink: _sink).refresh(
        todayWalkCount: count,
        dogName: widget.dogName,
        now: widget.now,
      );
      _lastCount = count;
      _scheduledAt = at;
    } catch (e) {
      // **홈은 살아 있어야 한다.** 알림은 곁다리 기능이고, 권한이 없거나 플러그인이
      // 없는 환경(웹·테스트 바인딩)에서 예약이 던지면 여기서 멈춘다 — 그 예외가 위로
      // 올라가면 요약 카드가 통째로 안 그려진다.
      if (kDebugMode) {
        debugPrint('[WalkReminder] 예약 실패: $e');
      }
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

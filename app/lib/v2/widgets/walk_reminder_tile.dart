// lib/v2/widgets/walk_reminder_tile.dart
//
// 설정의 "저녁 산책 알림" 한 줄 — 이슈 #341.
//
// ## 켜는 순간에만 권한을 묻는다
//
// 앱을 처음 여는 사람에게 알림 권한부터 묻는 화면은 대부분 거절당하고, 거절당한 뒤에는
// 다시 물을 수 없다. 그래서 이 스위치를 켜는 순간에만 묻는다 — **무엇을 위한 권한인지**
// 바로 위 줄에 적혀 있는 상태에서 묻는 것이 승낙률과 정직함 둘 다에 낫다.
//
// 거절당하면 스위치를 되돌린다. 켜진 채로 두면 "켰는데 안 온다" 가 된다.
import 'package:flutter/material.dart';

import '../data/local_notification_sink.dart';
import '../data/walk_feed.dart';
import '../data/walk_reminder.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';

class WalkReminderTile extends StatefulWidget {
  const WalkReminderTile({
    super.key,
    this.store = const WalkReminderStore(),
    this.sink,
    this.requestPermission,
    this.todayWalkCount,
  });

  final WalkReminderStore store;

  /// 예약을 거는 자리. 테스트가 가짜를 꽂는다.
  final WalkReminderSink? sink;

  /// 권한을 묻는 자리. `null` 이면 진짜 플러그인에게 묻는다. `false` 를 주면 스위치가
  /// 되돌아간다 — 테스트가 그 갈래를 잰다.
  final Future<bool> Function()? requestPermission;

  /// 오늘 몇 번 걸었나. **켜는 그 자리에서 알아야 한다** — 이미 걸은 날 저녁에 알림이
  /// 울리면 그건 틀린 알림이다. `null` 이면 산책 자료를 한 번 읽는다.
  final Future<int> Function()? todayWalkCount;

  @override
  State<WalkReminderTile> createState() => _WalkReminderTileState();
}

class _WalkReminderTileState extends State<WalkReminderTile> {
  WalkReminderSettings _settings = const WalkReminderSettings();
  bool _loaded = false;
  LocalNotificationSink? _realSink;

  WalkReminderSink get _sink => widget.sink ?? (_realSink ??= LocalNotificationSink());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.store.read();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loaded = true;
    });
  }

  /// 저장하고 **그 자리에서 예약을 다시 건다.** 설정만 바꾸고 예약을 안 고치면
  /// 다음에 앱을 열 때까지 옛 시각에 울린다.
  Future<void> _apply(WalkReminderSettings next) async {
    await widget.store.save(next);
    if (!mounted) return;
    setState(() => _settings = next);

    final count = await (widget.todayWalkCount ??
        () async => (await WalkFeed().load()).today.count)();
    await WalkReminder(sink: _sink, store: widget.store).refresh(
      todayWalkCount: count,
      dogName: kMyDog.value?.name,
    );
  }

  Future<void> _toggle(bool on) async {
    if (!on) {
      await _apply(_settings.copyWith(enabled: false));
      return;
    }
    final granted = await (widget.requestPermission ??
        () => (_sink as LocalNotificationSink).requestPermission())();
    if (!mounted) return;
    if (!granted) {
      // 거절당했다. 스위치를 되돌리고 왜 안 되는지 말한다 — 켜진 채로 두면
      // "켰는데 안 온다" 가 되고, 그건 앱이 고장 난 것으로 읽힌다.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('기기 설정에서 알림을 허용해 주세요'),
      ));
      return;
    }
    await _apply(_settings.copyWith(enabled: true));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
      helpText: '언제 알려 드릴까요',
    );
    if (picked == null) return;
    await _apply(_settings.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const Icon(Icons.notifications_active_outlined, size: 20, color: T.textSecondary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('저녁 산책 알림',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
              SizedBox(height: 2),
              Text('그날 산책 기록이 없을 때만 한 번 울려요',
                  style: TextStyle(fontSize: 12, color: T.textMuted)),
            ]),
          ),
          Switch(value: _settings.enabled, onChanged: _toggle),
        ]),
      ),
      if (_settings.enabled) ...[
        Container(height: 1, color: T.accentSoft),
        GestureDetector(
          onTap: _pickTime,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              const SizedBox(width: 32),
              const Text('알림 시각',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
              const Spacer(),
              Text(_settings.timeLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: T.warmText)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: T.textFaint),
            ]),
          ),
        ),
      ],
    ]);
  }
}

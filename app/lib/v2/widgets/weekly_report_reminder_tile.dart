// lib/v2/widgets/weekly_report_reminder_tile.dart
//
// 설정의 "일요일 저녁 주간 정리" 스위치 — `walk_reminder_tile.dart` 와 같은 절차: 켤 때만 권한을 묻고,
// 거절당하면 켜진 채로 두지 않는다("켰는데 안 온다" 를 만들지 않는다).
import 'package:flutter/material.dart';

import '../data/local_notification_sink.dart';
import '../data/weekly_report_reminder.dart';
import '../theme/app_tokens.dart';

class WeeklyReportReminderTile extends StatefulWidget {
  const WeeklyReportReminderTile({
    super.key,
    this.store = const WeeklyReportReminderStore(),
    this.sink,
    this.requestPermission,
    this.now,
  });

  final WeeklyReportReminderStore store;
  final WeeklyReportReminderSink? sink;
  final Future<bool> Function()? requestPermission;
  final DateTime? now;

  @override
  State<WeeklyReportReminderTile> createState() => _WeeklyReportReminderTileState();
}

class _WeeklyReportReminderTileState extends State<WeeklyReportReminderTile> {
  WeeklyReportReminderSettings _settings = const WeeklyReportReminderSettings();
  bool _loaded = false;
  LocalNotificationSink? _realSink;

  WeeklyReportReminderSink get _sink => widget.sink ?? (_realSink ??= LocalNotificationSink());

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

  Future<void> _apply(WeeklyReportReminderSettings next) async {
    await widget.store.save(next);
    if (!mounted) return;
    setState(() => _settings = next);
    await WeeklyReportReminder(sink: _sink, store: widget.store).refresh(now: widget.now);
  }

  Future<void> _toggle(bool on) async {
    if (!on) {
      await _apply(const WeeklyReportReminderSettings(enabled: false));
      return;
    }
    final granted = await (widget.requestPermission ??
        () => (_sink as LocalNotificationSink).requestPermission())();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('기기 설정에서 알림을 허용해 주세요'),
      ));
      return;
    }
    await _apply(const WeeklyReportReminderSettings(enabled: true));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        const Icon(Icons.event_note_outlined, size: 20, color: T.textSecondary),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('일요일 저녁 주간 정리',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            SizedBox(height: 2),
            Text('매주 일요일 오후 7시, 이번 주 요약을 보러 오라고 한 번 울려요',
                style: TextStyle(fontSize: 12, color: T.textMuted)),
          ]),
        ),
        Switch(key: const Key('weekly-report-switch'), value: _settings.enabled, onChanged: _toggle),
      ]),
    );
  }
}

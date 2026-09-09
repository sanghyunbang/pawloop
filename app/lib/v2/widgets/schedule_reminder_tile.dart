// 설정의 "일정 알림" 한 줄 — 이슈 #420.
//
// ## 기본은 "없음" 이다
//
// 묻지 않고 알림을 보내는 앱이 되면 안 된다 — 저녁 산책 알림(#341)이 고른 것과 같은 답이다.
// 켜는 것은 사용자가 여기서 하는 일이고, 무엇이 오는지 이 자리에 적어 둔다.
//
// ## 한계를 숨기지 않는다
//
// 이 알림은 **이 기기가 스스로** 건다. 담당자가 다른 사람이면 그 사람 기기에는 안 뜬다.
// 그 문장을 부제로 둔다 — 안 두면 사용자는 "아빠 담당" 이라고 적어 두고 아빠가 알림을 받을
// 거라고 믿는다.
import 'package:flutter/material.dart';

import '../domain/schedule_reminder.dart';
import '../theme/app_tokens.dart';

class ScheduleReminderTile extends StatefulWidget {
  /// 테스트가 갈아 끼운다.
  final ScheduleReminderStore store;

  const ScheduleReminderTile({super.key, this.store = const ScheduleReminderStore()});

  @override
  State<ScheduleReminderTile> createState() => _ScheduleReminderTileState();
}

class _ScheduleReminderTileState extends State<ScheduleReminderTile> {
  ScheduleReminderWhen _when = ScheduleReminderWhen.none;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final when = await widget.store.read();
    if (!mounted) return;
    setState(() {
      _when = when;
      _loaded = true;
    });
  }

  Future<void> _pick(ScheduleReminderWhen next) async {
    setState(() => _when = next);
    await widget.store.save(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 64);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('일정 알림',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 2),
        const Text('적어 둔 일정을 미리 알려 줍니다. 이 기기에만 오고, 담당자가 다른 분이면 '
            '그분께는 안 갑니다.',
            style: TextStyle(fontSize: 12, color: T.textMuted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final w in ScheduleReminderWhen.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(w),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _when == w ? T.sigEnd : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _when == w ? T.sigEnd : T.cardBorder),
                ),
                child: Text(w.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _when == w ? Colors.white : T.textSecondary)),
              ),
            ),
        ]),
        if (_when != ScheduleReminderWhen.none) ...[
          const SizedBox(height: 8),
          Text(
            _when == ScheduleReminderWhen.eveningBefore
                ? '전날 저녁 8시에 알려 드려요'
                : '당일 아침 8시에 알려 드려요',
            style: const TextStyle(fontSize: 12, color: T.textSecondary),
          ),
          const SizedBox(height: 2),
          // 예약이 언제 걸리는지 숨기지 않는다 — 안 적으면 "켰는데 왜 안 와요" 가 된다.
          const Text('일정 탭을 열 때 예약을 다시 겁니다',
              style: TextStyle(fontSize: 12, color: T.textMuted)),
        ],
      ]),
    );
  }
}

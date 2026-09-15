// lib/v2/widgets/walk_goal_row.dart
//
// 홈의 주간 목표 한 줄 — 이슈 #341.
//
// ## 무엇을 보여 주나
//
//   [▓▓▓▓▓░░░░]  이번 주 3/5일 · 42/90분      3일째
//
// 막대 하나에 숫자 둘을 얹는다. **덜 찬 쪽으로 채운다**(`WalkGoalProgress.ratio`) —
// 몰아 걷기가 "다 했다" 로 보이면 목표가 뜻을 잃는다.
//
// ## 혼내지 않는다
//
// 연속이 끊겨도 "0일" 이라고 쓰지 않는다. 그 자리는 비우고, 대신 이번 주 날 수를 말한다.
// 목표를 못 채운 주에도 문장은 같은 크기·같은 색이다 — 앱이 사람을 나무라기 시작하면
// 그 앱을 여는 것 자체가 부담이 된다.
//
// 오늘 아직 안 걸었어도 어제까지의 연속은 살아 있다(`walkStreakDays`) — 저녁 7시에
// "0일" 을 보여 주면 아직 나갈 수 있는 사람에게 이미 끊겼다고 말하는 셈이다.
import 'package:flutter/material.dart';

import '../data/walk_feed.dart';
import '../data/walk_goal_store.dart';
import '../domain/pet.dart';
import '../domain/walk_goal.dart';
import '../theme/app_tokens.dart';

class WalkGoalRow extends StatefulWidget {
  const WalkGoalRow({
    super.key,
    required this.dog,
    required this.data,
    this.store = const WalkGoalStore(),
    this.now,
  });

  /// 목표를 제안할 아이. `null` 이거나 개가 아니면 **줄 자체를 안 그린다**.
  final DogProfile? dog;

  final WalkFeedData data;

  /// 테스트가 꽂는 자리.
  final WalkGoalStore store;

  /// 테스트가 오늘을 정한다. 연속 일수가 날짜에 걸려 있어 실제 시계로 재면 자정에 깨진다.
  final DateTime? now;

  @override
  State<WalkGoalRow> createState() => _WalkGoalRowState();
}

class _WalkGoalRowState extends State<WalkGoalRow> {
  WalkGoal? _saved;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    kWalkGoalRev.addListener(_load);
  }

  @override
  void dispose() {
    kWalkGoalRev.removeListener(_load);
    super.dispose();
  }

  @override
  void didUpdateWidget(WalkGoalRow old) {
    super.didUpdateWidget(old);
    // 아이를 바꾸면 목표도 그 아이 것으로 다시 읽는다 — 소형견과 대형견은 두 배 다르다.
    if (old.dog?.serverId != widget.dog?.serverId) _load();
  }

  Future<void> _load() async {
    final saved = await widget.store.read(petId: widget.dog?.serverId);
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loaded = true;
    });
  }

  /// 세운 목표가 있으면 그것, 없으면 크기·나이로 제안한 값.
  WalkGoal? get _goal {
    final dog = widget.dog;
    if (dog == null) return null;
    return _saved ??
        WalkGoal.recommendedFor(
          species: dog.species,
          size: dog.size,
          ageMonths: dog.ageMonths,
        );
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    // 아직 안 읽었으면 빈 자리다 — 제안값을 먼저 그렸다가 저장값으로 바뀌면 숫자가 튄다.
    if (!_loaded || goal == null) return const SizedBox.shrink();

    // 숫자를 모르면 **달성치를 주장하지 않는다**(#568). `0/5일 · 0/150분` 과 빈 막대는
    // 문장이 아니라 주장이라, 못 읽은 주를 "아무것도 안 한 주" 로 만든다. 목표는 기기에
    // 저장된 값이라 서버가 죽어도 사실이므로 그것만 남긴다.
    final unknown = widget.data.numbersUnknown;
    final progress = WalkGoalProgress(
      goal: goal,
      days: widget.data.daysWalkedThisWeek,
      minutes: widget.data.minutesThisWeek,
    );
    final streak = walkStreakDays(
      widget.data.walkedDates,
      today: widget.now ?? DateTime.now(),
    );

    return GestureDetector(
      onTap: _edit,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(height: 1, color: T.accentSoft),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('이번 주 목표',
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textMuted)),
                const SizedBox(width: 6),
                Text(
                    unknown
                        ? '${goal.daysPerWeek}일 · ${goal.minutesPerWeek}분'
                        : progress.label,
                    key: const Key('walk-goal-label'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: unknown
                          ? T.textMuted
                          : (progress.met ? const Color(0xFF4CAF88) : T.textSecondary),
                    )),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                // 모를 때는 **막대 자체를 안 그린다**. 값 0 으로 두면 "하나도 못 채웠다"
                // 로 읽히고, 도는 스피너로 두면 "읽는 중" 이라는 또 다른 거짓말이 된다.
                child: unknown
                    ? Container(height: 7, color: T.accentSoft)
                    : LinearProgressIndicator(
                        value: progress.ratio,
                        minHeight: 7,
                        backgroundColor: T.accentSoft,
                        valueColor: AlwaysStoppedAnimation(
                          progress.met ? const Color(0xFF4CAF88) : T.warmMid,
                        ),
                      ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          // 끊겼으면 이 자리를 비운다. "0일" 은 혼내는 말이다.
          if (streak > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x1FFF8F63),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$streak일째',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: T.warmText)),
            )
          else
            const Icon(Icons.chevron_right, size: 18, color: T.textFaint),
        ]),
      ]),
    );
  }

  Future<void> _edit() async {
    final goal = _goal;
    if (goal == null) return;
    final dog = widget.dog!;
    final picked = await WalkGoalSheet.open(
      context,
      current: goal,
      recommended: WalkGoal.recommendedFor(
            species: dog.species,
            size: dog.size,
            ageMonths: dog.ageMonths,
          ) ??
          goal,
    );
    if (picked == null) return;
    await widget.store.save(picked, petId: dog.serverId);
  }
}

/// 목표를 고치는 시트. 날 수와 분을 각각 스텝퍼로 올린다.
class WalkGoalSheet {
  const WalkGoalSheet._();

  static Future<WalkGoal?> open(
    BuildContext context, {
    required WalkGoal current,
    required WalkGoal recommended,
  }) =>
      showModalBottomSheet<WalkGoal>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _GoalSheetBody(current: current, recommended: recommended),
      );
}

class _GoalSheetBody extends StatefulWidget {
  const _GoalSheetBody({required this.current, required this.recommended});

  final WalkGoal current;
  final WalkGoal recommended;

  @override
  State<_GoalSheetBody> createState() => _GoalSheetBodyState();
}

class _GoalSheetBodyState extends State<_GoalSheetBody> {
  late int _days = widget.current.daysPerWeek;
  late int _minutes = widget.current.minutesPerWeek;

  /// 분은 10 단위로 움직인다 — 1분씩 올리게 두면 목표를 정하는 데 스무 번을 눌러야 한다.
  static const _minuteStep = 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x1F463C64),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('이번 주 산책 목표',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 6),
          Text(WalkGoal.sourceLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: T.textMuted)),
          const SizedBox(height: 18),
          _stepper(
            label: '주 며칠',
            value: '$_days일',
            onMinus: _days > 1 ? () => setState(() => _days--) : null,
            onPlus: _days < 7 ? () => setState(() => _days++) : null,
          ),
          const SizedBox(height: 10),
          _stepper(
            label: '주 몇 분',
            value: '$_minutes분',
            onMinus: _minutes > _minuteStep
                ? () => setState(() => _minutes -= _minuteStep)
                : null,
            onPlus: () => setState(() => _minutes += _minuteStep),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() {
              _days = widget.recommended.daysPerWeek;
              _minutes = widget.recommended.minutesPerWeek;
            }),
            behavior: HitTestBehavior.opaque,
            child: Text(
              '제안값으로 — 주 ${widget.recommended.daysPerWeek}일 · ${widget.recommended.minutesPerWeek}분',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText),
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .pop(WalkGoal(daysPerWeek: _days, minutesPerWeek: _minutes)),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [T.warmStart, T.warmEnd],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text('이 목표로 할게요',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stepper({
    required String label,
    required String value,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4FC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const Spacer(),
          _round(Icons.remove, onMinus),
          SizedBox(
            width: 74,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
          _round(Icons.add, onPlus),
        ]),
      );

  Widget _round(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null ? const Color(0x0F463C64) : Colors.white,
          ),
          child: Icon(icon,
              size: 18, color: onTap == null ? const Color(0x40463C64) : T.textSecondary),
        ),
      );
}

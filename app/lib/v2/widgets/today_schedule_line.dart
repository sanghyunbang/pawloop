// 홈의 "오늘 할 일" 한 줄 — 이슈 #420 (부모 #416).
//
// ## 없으면 줄 자체가 없다
//
// "오늘 할 일 0" 은 자리만 차지한다. 홈은 이미 카드가 여럿이라, 아무것도 안 말하는 줄이
// 하나 더 붙으면 사용자는 그만큼 아래로 밀린 것을 못 본다. 그래서 이 위젯은 **아무것도
// 없으면 `SizedBox.shrink()`** 다 — 실패했을 때도 마찬가지다.
//
// ## 게스트에게는 아예 안 묻는다
//
// 로그인 안 한 사람에게 일정은 없다 — 물으면 401 이 돌아오고, 그동안 12초짜리 타임아웃
// 타이머가 떠 있다. 오늘의 케어 카드가 같은 자리에서 같은 답을 쓴다(`AuthState.hasNoToken`).
// **게스트가 아니라 "토큰이 없다"** 로 재는 이유는 #673 에 있다 — 소셜 왕복 중에도 토큰은
// 없는데, 이 줄이 상태 알림을 듣고 다시 읽으므로 버튼을 누른 그 순간 요청이 나갔다.
//
// ## 실패해도 조용하다
//
// 못 불러오면 "불러오지 못했어요" 를 안 적는다. 오늘의 케어 카드와 다른 답인 것이 의도다 —
// 거기는 사용자가 **누르러 온 자리**라 안 되면 말해야 하지만, 여기는 지나가다 보는 한 줄이고,
// 못 본다고 잃는 것이 없다. 일정 탭이 같은 것을 제대로 말한다.
//
// ## 일정이 바뀌면 다시 읽는다 (#741)
//
// 바로 위의 케어 카드가 병원 기록을 하면서 오늘 병원 일정을 완료로 바꿀 수 있다. 그때 이 줄이
// "할 일 1 · 병원" 을 계속 들고 있으면 방금 한 일이 안 끝난 것처럼 보인다 — `kScheduleRev` 를
// 듣고 다시 읽는다.
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/schedule_repository.dart';
import '../domain/schedule.dart';
import '../theme/app_tokens.dart';

class TodayScheduleLine extends StatefulWidget {
  /// 테스트가 갈아 끼운다.
  final ScheduleRepository? repository;

  /// "오늘". 테스트가 고정하지 않으면 기기 시계다.
  final DateTime? today;

  /// 누르면 어디로. 홈이 일정 탭으로 보낸다.
  final VoidCallback? onOpen;

  const TodayScheduleLine({super.key, this.repository, this.today, this.onOpen});

  @override
  State<TodayScheduleLine> createState() => _TodayScheduleLineState();

  /// `할 일 2 · 병원(아빠) · 목욕` 꼴.
  ///
  /// 제목이 아니라 **종류**를 적는다 — 제목은 사람이 쓴 문장이라 길이를 알 수 없고, 한 줄에
  /// 둘을 넣으면 첫 번째부터 잘린다. 담당자가 있으면 괄호로 붙인다: 누가 할 일인지가
  /// "무엇을" 만큼 자주 헷갈리는 값이다.
  ///
  /// 셋을 넘으면 앞의 둘만 적는다. 그 뒤는 세지 않고 잘라 낸다 — 개수는 이미 맨 앞에 있다.
  static String summarize(List<Schedule> open) {
    final shown = open.take(2).map((s) {
      final who = s.assignee?.nickname;
      return who == null ? s.kind.label : '${s.kind.label}($who)';
    });
    return ['할 일 ${open.length}', ...shown].join(' · ');
  }
}

class _TodayScheduleLineState extends State<TodayScheduleLine> {
  late final ScheduleRepository _repo = widget.repository ?? ScheduleRepository();

  List<Schedule> _items = const [];

  @override
  void initState() {
    super.initState();
    // 로그인 상태가 나중에 바뀌면 그때 다시 묻는다 — 처음 열 때는 아직 게스트일 수 있다.
    AuthState.status.addListener(_load);
    kScheduleRev.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AuthState.status.removeListener(_load);
    kScheduleRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // 토큰이 없으면 안 부른다 — 게스트뿐 아니라 **소셜 왕복 중**도 그렇다(#673).
    if (AuthState.hasNoToken) {
      if (mounted && _items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    final today = widget.today ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    try {
      final items = await _repo.range(from: day, to: day);
      if (!mounted) return;
      // 이미 한 것은 "할 일" 이 아니다. 건너뛴 것도 마찬가지다.
      setState(() => _items = items.where((s) => s.status.isOpen).toList()
        ..sort(Schedule.compare));
    } on ScheduleFailure {
      // 조용하다 — 파일 머리말 참조.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: T.cardBorder),
        ),
        child: Row(children: [
          const Icon(Icons.event_note_outlined, size: 18, color: T.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              TodayScheduleLine.summarize(_items),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: T.textPrimary),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: T.textMuted),
        ]),
      ),
    );
  }

}

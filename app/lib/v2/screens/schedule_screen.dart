// 일정표 — 달력 · 그날 목록 · 만들기 시트 (이슈 #419, 서버는 #418).
//
// ## 주인을 사용자가 안 고른다
//
// 계약에는 주인이 셋이지만(아이 · 가족 그룹 · 크루) 시트에 "이건 누구 것인가요" 를 물으면
// 사용자가 **가시성을 고르는 질문**을 받게 된다 — 아이 소유 일정은 그 아이의 주인만 보고,
// 가족 소유 일정은 가족이 함께 본다. 그건 화면이 알아서 정할 수 있는 것이다.
//
//   * 가족 그룹이 있으면 → `group` 이다. 일정표를 쓰는 이유가 "가족이 함께 본다" 라서다.
//   * 없으면 → `dog` 이고, 그때는 아이를 고르는 것이 필수다(`ownerRef` 가 그 아이다).
//
// 시트가 그 결과를 한 줄로 말한다 — "우리 가족이 함께 봅니다" / "이 일정은 나만 봅니다".
// 고르게 하지 않되 숨기지도 않는다.
//
// ## 달력 칸에 숫자를 안 적는다
//
// 종류별 **점**만 찍는다. 한 칸이 좁아서 "3" 같은 숫자를 적으면 무엇이 셋인지 알 수 없고,
// 점 세 개면 색으로 병원인지 산책인지가 바로 보인다. 넷 이상이면 `+` 하나로 접는다.
import 'package:flutter/material.dart';

import '../data/family_repository.dart';
import '../data/schedule_repository.dart';
import '../domain/pet.dart';
import '../domain/schedule.dart';
import '../domain/schedule_reminder.dart';
import '../theme/app_tokens.dart';

/// 목록을 무엇으로 거를까. `전체` 가 기본이다 — 달력의 기본이 합쳐 보기다.
class ScheduleFilter {
  /// `null` 이면 전부.
  final int? dogId;

  /// 가족 것만.
  final bool groupOnly;

  const ScheduleFilter({this.dogId, this.groupOnly = false});

  static const all = ScheduleFilter();

  bool get isAll => dogId == null && !groupOnly;
}

class ScheduleScreen extends StatefulWidget {
  /// 테스트가 갈아 끼운다. 없으면 진짜를 만든다.
  final ScheduleRepository? repository;
  final FamilyRepository? familyRepository;

  /// 알림을 실제로 거는 자리. **위젯 테스트는 반드시 갈아끼운다** — 진짜는
  /// `flutter_local_notifications` 를 부르고, 테스트 바인딩에는 그 채널이 없어 던진다.
  final ScheduleReminderSink? reminderSink;

  /// 알림 설정 저장소.
  final ScheduleReminderStore reminderStore;

  /// "오늘". 테스트가 고정하지 않으면 기기 시계다.
  final DateTime? today;

  const ScheduleScreen({
    super.key,
    this.repository,
    this.familyRepository,
    this.today,
    this.reminderSink,
    this.reminderStore = const ScheduleReminderStore(),
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final ScheduleRepository _repo = widget.repository ?? ScheduleRepository();
  late final FamilyRepository _family = widget.familyRepository ?? FamilyRepository();

  late final DateTime _today = _dayOf(widget.today ?? DateTime.now());

  late DateTime _month = DateTime(_today.year, _today.month);
  late DateTime _selected = _today;

  ScheduleFilter _filter = ScheduleFilter.all;

  List<Schedule> _items = const [];
  bool _loading = true;
  ScheduleFailureKind? _failure;

  /// 우리 가족 그룹. 없으면 `null` 이고, 그때 새 일정은 아이 소유가 된다.
  int? _groupId;
  bool _groupResolved = false;

  /// 담당자로 고를 수 있는 사람들. 가족이 없으면 비어 있다.
  List<ScheduleMember> _members = const [];

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    if (!_groupResolved) {
      try {
        final group = await _family.myGroup();
        _groupId = group.id;
        _members = group.members
            .map((m) => ScheduleMember(userId: m.userId, nickname: m.nickname))
            .toList();
      } on FamilyFailure {
        // 가족이 없는 것은 오류가 아니다 — 혼자 쓰면 아이 소유 일정이 된다.
        _groupId = null;
        _members = const [];
      }
      _groupResolved = true;
    }

    try {
      final items = await _repo.range(
        from: _month,
        to: _lastDayOfMonth(_month),
        ownerKind: _filter.groupOnly ? ScheduleOwnerKind.group : null,
        ownerRef: _filter.groupOnly ? _groupId : null,
        dogId: _filter.dogId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      await _refreshReminders();
    } on ScheduleFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.kind;
        _loading = false;
      });
    }
  }

  static DateTime _lastDayOfMonth(DateTime month) =>
      DateTime(month.year, month.month + 1, 0);

  /// 이 달의 일정으로 알림을 다시 건다 — 이슈 #420.
  ///
  /// **이 화면을 열 때만 걸린다.** 사용자가 일정 탭을 한 번도 안 열면 예약도 없다. 서버가
  /// 보내는 푸시(#83)가 서기 전까지는 그것이 한계고, 만들기 시트가 그 사실을 말한다.
  ///
  /// 실패해도 조용하다 — 알림은 곁다리이고, 그것 때문에 달력이 안 그려지면 안 된다.
  Future<void> _refreshReminders() async {
    final sink = widget.reminderSink;
    if (sink == null) return;
    try {
      final when = await widget.reminderStore.read();
      await sink.replaceAll(planReminders(
        schedules: _items,
        when: when,
        // `widget.today` 는 테스트가 고정하는 값이다. 여기서 `DateTime.now()` 를 그대로
        // 쓰면 "지나간 일정에는 안 건다" 가 테스트 안에서 성립하지 않는다 — 테스트의
        // 10월과 기계의 9월이 다른 달이기 때문이다(실측으로 걸렸다).
        now: widget.today ?? DateTime.now(),
      ));
    } catch (_) {
      // 알림을 못 걸어도 화면은 그대로다.
    }
  }

  void _goMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // 고른 날이 이 달 밖이면 1일로 옮긴다 — 안 옮기면 목록이 늘 비어 보인다.
      if (_selected.year != _month.year || _selected.month != _month.month) {
        _selected = _month;
      }
    });
    _load();
  }

  List<Schedule> get _visible => _items.toList()..sort(Schedule.compare);

  List<Schedule> get _ofSelectedDay =>
      _visible.where((s) => s.isOn(_selected)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: SafeArea(
        bottom: false,
        // 아이 목록은 셸의 `PetLoader` 가 채운다(#159) — 이 화면보다 **늦게** 올 수 있다.
        // 값을 한 번만 읽으면 그날 처음 연 사람에게는 필터 칩이 영영 "전체" 하나뿐이고,
        // 목록의 아이 이름도 안 뜬다.
        child: ValueListenableBuilder<List<DogProfile>>(
          valueListenable: kMyPets,
          builder: (_, __, ___) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _filterChips(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
                  children: [
                    _calendar(),
                    const SizedBox(height: 14),
                    _dayList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // 떠 있는 알약 네비(높이 66 + 아래 여백 8)가 화면 바닥을 덮고 있다. 기본 자리에
      // 두면 버튼이 그 위에 겹쳐 "채팅" 탭을 가린다 — 그만큼 올려 둔다.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 92),
        child: FloatingActionButton(
          onPressed: _openCreateSheet,
          backgroundColor: T.sigEnd,
          tooltip: '일정 추가',
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }

  // ─────────────────────── 머리말 ───────────────────────

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text('${_month.year}년 ${_month.month}월',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
          IconButton(
            onPressed: () => _goMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: '지난 달',
            color: T.textSecondary,
          ),
          IconButton(
            onPressed: () => _goMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: '다음 달',
            color: T.textSecondary,
          ),
        ]),
      );

  Widget _filterChips() {
    final pets = kMyPets.value.where((p) => p.serverId != null).toList();
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? T.sigEnd : T.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? T.sigEnd : T.cardBorder),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : T.textSecondary)),
            ),
          ),
        );

    void pick(ScheduleFilter next) {
      setState(() => _filter = next);
      _load();
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('전체', _filter.isAll, () => pick(ScheduleFilter.all)),
          for (final pet in pets)
            chip(pet.name, _filter.dogId == pet.serverId,
                () => pick(ScheduleFilter(dogId: pet.serverId))),
          if (_groupId != null)
            chip('가족', _filter.groupOnly,
                () => pick(const ScheduleFilter(groupOnly: true))),
        ],
      ),
    );
  }

  // ─────────────────────── 달력 ───────────────────────

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month);
    // 일요일부터 시작한다. DateTime.weekday 는 월=1 … 일=7 이라 일요일이 0 이 되게 옮긴다.
    final lead = first.weekday % 7;
    final days = _lastDayOfMonth(_month).day;
    final cells = <Widget>[];

    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= days; d++) {
      final day = DateTime(_month.year, _month.month, d);
      cells.add(_dayCell(day));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: T.cardBg,
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(color: T.cardBorder),
        boxShadow: T.cardShadow,
      ),
      child: Column(children: [
        Row(
          children: [
            for (final name in const ['일', '월', '화', '수', '목', '금', '토'])
              Expanded(
                child: Center(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: T.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.82,
          children: cells,
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime day) {
    final ofDay = _visible.where((s) => s.isOn(day)).toList();
    final isSelected = _dayOf(day) == _dayOf(_selected);
    final isToday = _dayOf(day) == _today;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = day),
      child: Semantics(
        button: true,
        selected: isSelected,
        // 한 칸을 **하나의 노드**로 읽는다. 안 묶으면 스크린리더가 "20" 다음에 아무 뜻
        // 없는 점 셋을 따로 읽고, 그날에 무엇이 있는지는 끝내 말하지 않는다.
        container: true,
        excludeSemantics: true,
        label: '${day.month}월 ${day.day}일'
            '${ofDay.isEmpty ? '' : ' · 일정 ${ofDay.length}건'}',
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? T.sigEnd : Colors.transparent,
              border: isToday && !isSelected
                  ? Border.all(color: T.sigEnd, width: 1.4)
                  : null,
            ),
            child: Text('${day.day}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? Colors.white : T.textPrimary)),
          ),
          const SizedBox(height: 3),
          // 숫자를 안 적는다 — 한 칸이 좁아 무엇이 셋인지 알 수 없다. 색이 종류를 말한다.
          SizedBox(
            height: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final s in ofDay.take(3))
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.status.isOpen ? s.kind.color : T.textFaint,
                    ),
                  ),
                if (ofDay.length > 3)
                  const Text('+',
                      style: TextStyle(
                          fontSize: 9, height: 1, color: T.textMuted)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────── 그날 목록 ───────────────────────

  Widget _dayList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failure != null) {
      return _notice(
        _failure == ScheduleFailureKind.network
            ? '일정을 불러오지 못했어요'
            : '이 일정은 볼 수 없어요',
        action: '다시 시도',
        onTap: _load,
      );
    }

    final ofDay = _ofSelectedDay;
    if (ofDay.isEmpty) {
      // 이 달에 아무것도 없는 것과, 이 날만 비어 있는 것은 다른 말이다. 둘을 같은 문구로
      // 뭉치면 20일에 병원 예약을 적어 둔 사람이 15일을 눌렀을 때 **"아직 적어 둔 일정이
      // 없어요"** 를 보게 되고, 그건 자기가 적은 것이 사라졌다는 뜻으로 읽힌다.
      return _items.isEmpty ? _emptyState() : _quietDay();
    }

    final timed = ofDay.where((s) => !s.isAllDay).toList();
    final allDay = ofDay.where((s) => s.isAllDay).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('${_selected.month}월 ${_selected.day}일',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
      ),
      for (final s in timed) _row(s),
      if (allDay.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 10, bottom: 6),
          child: Text('하루 종일',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: T.textMuted)),
        ),
        for (final s in allDay) _row(s),
      ],
    ]);
  }

  Widget _emptyState() => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.cardBorder),
        ),
        child: Column(children: [
          const Icon(Icons.event_available_outlined, size: 34, color: T.textFaint),
          const SizedBox(height: 10),
          const Text('아직 적어 둔 일정이 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text('병원 예약부터 적어 볼까요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: T.textSecondary)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _openCreateSheet,
            style: FilledButton.styleFrom(backgroundColor: T.sigEnd),
            child: const Text('일정 적기'),
          ),
        ]),
      );

  Widget _quietDay() => Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.cardBorder),
        ),
        child: Column(children: [
          Text('${_selected.month}월 ${_selected.day}일은 비어 있어요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text('점이 찍힌 날에 이 달의 일정이 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: T.textMuted)),
        ]),
      );

  Widget _notice(String text, {String? action, VoidCallback? onTap}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.cardBorder),
        ),
        child: Column(children: [
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: T.textSecondary)),
          if (action != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ]),
      );

  Widget _row(Schedule s) {
    final dog = _petName(s.dogId);
    final parts = <String>[
      if (dog != null) dog,
      if (s.assignee != null) '${s.assignee!.nickname} 담당',
      if (!s.isAllDay) Schedule.formatTime(s.atTime!),
      // 되풀이하는 것은 그렇다고 말한다 — 안 적으면 "왜 매주 있지" 를 사용자가 푼다.
      if (s.repeats) s.repeatKind.label,
    ];
    final done = !s.status.isOpen;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditSheet(s),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: T.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: T.cardBorder),
      ),
      child: Row(children: [
        Icon(s.kind.icon, size: 20, color: done ? T.textFaint : s.kind.color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: done ? T.textMuted : T.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                )),
            if (parts.isNotEmpty)
              Text(parts.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: T.textMuted)),
          ]),
        ),
        IconButton(
          onPressed: () => _toggle(s),
          tooltip: done ? '아직 안 함으로' : '완료로',
          icon: Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: done ? T.auroraMint : T.textFaint,
          ),
        ),
      ]),
      ),
    );
  }

  String? _petName(int? dogId) {
    if (dogId == null) return null;
    for (final p in kMyPets.value) {
      if (p.serverId == dogId) return p.name;
    }
    return null;
  }

  // ─────────────────────── 쓰기 ───────────────────────

  Future<void> _toggle(Schedule s) async {
    final next =
        s.status.isOpen ? ScheduleStatus.done : ScheduleStatus.planned;
    try {
      final updated = await _repo.mark(s, next);
      if (!mounted) return;
      setState(() => _items = _replace(_items, updated));
    } on ScheduleFailure catch (e) {
      if (!mounted) return;
      _handleFailure(e);
    }
  }

  /// 충돌은 "실패" 가 아니다 — 남이 먼저 고친 것이고, 그 최신 값이 함께 온다.
  ///
  /// 조용히 덮어쓰지 않는다. 화면을 최신 값으로 바꾸고 누가 고쳤는지를 말한다.
  void _handleFailure(ScheduleFailure e) {
    if (e.kind == ScheduleFailureKind.conflict) {
      final current = e.current;
      if (current != null) {
        setState(() => _items = _replace(_items, current));
      }
      final who = current?.updatedBy?.nickname;
      _say(who == null
          ? '다른 분이 방금 고쳤어요. 최신 내용으로 바꿨어요.'
          : '$who님이 방금 고쳤어요. 최신 내용으로 바꿨어요.');
      return;
    }
    _say(switch (e.kind) {
      ScheduleFailureKind.notFound => '이미 지워진 일정이에요.',
      ScheduleFailureKind.invalid => e.message ?? '이 일정은 아직 만들 수 없어요.',
      _ => '연결이 불안정해요. 잠시 뒤 다시 해 주세요.',
    });
  }

  void _say(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// 바뀐 줄 하나를 갈아 끼운다.
  ///
  /// **키가 `(id, onDate)` 다**(#421). 되풀이하는 규칙은 여러 날이 같은 id 를 나눠 쓰므로,
  /// id 만 보면 완료 표시 하나가 그 규칙의 모든 날에 번진다.
  static List<Schedule> _replace(List<Schedule> items, Schedule updated) =>
      items.map((s) => s.key == updated.key ? updated : s).toList();


  /// 고치기 시트를 연다 — 이슈 #421.
  ///
  /// **펼쳐 낸 하루면 먼저 묻는다** — "이 날만" 인지 "앞으로 전부" 인지. 안 물으면 사용자가
  /// 이번 주 목욕을 옮기려다 매주 목욕의 시각을 통째로 바꾼다.
  Future<void> _openEditSheet(Schedule s) async {
    bool onlyThisDay = false;
    if (s.occurrence) {
      final scope = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('되풀이하는 일정이에요',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: Text('${s.onDate.month}월 ${s.onDate.day}일만 고치기'),
              subtitle: const Text('나머지 날은 그대로예요'),
              onTap: () => Navigator.of(sheetContext).pop('day'),
            ),
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: const Text('앞으로 전부 고치기'),
              subtitle: const Text('반복 규칙 자체를 바꿔요'),
              onTap: () => Navigator.of(sheetContext).pop('rule'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (scope == null || !mounted) return;
      onlyThisDay = scope == 'day';
    }

    final pets = kMyPets.value.where((p) => p.serverId != null).toList();
    final saved = await showModalBottomSheet<Schedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScheduleSheet(
        repository: _repo,
        groupId: _groupId,
        pets: pets,
        members: _members,
        day: s.onDate,
        editing: s,
        onlyThisDay: onlyThisDay,
      ),
    );
    if (saved == null || !mounted) return;
    // 무엇이 바뀌었는지(규칙인지 하루인지) 화면이 스스로 셀 수 없다 — 다시 불러온다.
    await _load();
  }

  Future<void> _openCreateSheet() async {
    final pets = kMyPets.value.where((p) => p.serverId != null).toList();
    if (_groupId == null && pets.isEmpty) {
      _say('먼저 아이를 등록하거나 가족을 만들어 주세요.');
      return;
    }

    final created = await showModalBottomSheet<Schedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScheduleSheet(
        repository: _repo,
        groupId: _groupId,
        pets: pets,
        members: _members,
        day: _selected,
      ),
    );
    if (created == null || !mounted) return;

    if (created.repeats) {
      // 되풀이하는 규칙은 **서버가 펼친다**(#421). 돌려받은 것은 규칙 한 줄뿐이라, 그것만
      // 목록에 끼워 넣으면 달력에 시작일 하루만 점이 찍힌다 — 매주로 저장했는데 다음 주가
      // 안 보인다(에뮬레이터에서 눈으로 잡았다).
      setState(() => _selected = created.onDate);
      await _load();
      return;
    }

    setState(() {
      _items = [..._items, created];
      _selected = created.onDate;
    });
  }
}

/// 일정 한 장 — 종류 → 제목 → 날짜/시각 → 아이 → 담당 → 반복 → 메모.
///
/// **만들기와 고치기가 같은 시트다.** 두 벌로 두면 칸이 늘 때마다 두 곳을 고쳐야 하고,
/// 한쪽을 빠뜨리면 "만들 때는 되는데 고칠 때는 안 되는" 칸이 생긴다.
///
/// **주인을 안 묻는다** — 화면 파일 머리말에 이유가 있다.
class ScheduleSheet extends StatefulWidget {
  final ScheduleRepository repository;

  /// 우리 가족. `null` 이면 이 일정은 아이 소유가 되고, 그때 아이 고르기가 필수다.
  final int? groupId;

  final List<DogProfile> pets;

  /// 담당자로 고를 수 있는 사람들. 가족이 없으면 비어 있고, 그때 담당 칸이 안 보인다.
  final List<ScheduleMember> members;

  final DateTime day;

  /// 고치는 중이면 그 일정. `null` 이면 새로 만드는 것이다.
  final Schedule? editing;

  /// 고치기가 **이 하루에만** 미치는가(#421). 펼쳐 낸 하루를 고칠 때 참이다.
  final bool onlyThisDay;

  const ScheduleSheet({
    super.key,
    required this.repository,
    required this.groupId,
    required this.pets,
    required this.day,
    this.members = const [],
    this.editing,
    this.onlyThisDay = false,
  });

  @override
  State<ScheduleSheet> createState() => _ScheduleSheetState();
}

/// 담당자 후보 한 명. 가족 화면이 이미 들고 있는 것과 같은 값이다.
class ScheduleMember {
  final int userId;
  final String nickname;

  const ScheduleMember({required this.userId, required this.nickname});
}

class _ScheduleSheetState extends State<ScheduleSheet> {
  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _memo = TextEditingController(text: widget.editing?.memo ?? '');

  late ScheduleKind _kind = widget.editing?.kind ?? ScheduleKind.vet;
  late DateTime _date = widget.editing?.onDate ?? widget.day;
  late TimeOfDay? _time = widget.editing?.atTime;
  late int? _dogId = widget.editing?.dogId;
  late int? _assignee = widget.editing?.assignee?.userId;
  late ScheduleRepeat _repeat = widget.editing?.repeatKind ?? ScheduleRepeat.none;
  late DateTime? _repeatUntil = widget.editing?.repeatUntil;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 가족이 없으면 아이가 주인이라 하나는 골라져 있어야 한다.
    if (widget.groupId == null && _dogId == null && widget.pets.isNotEmpty) {
      _dogId = widget.pets.first.serverId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _memo.dispose();
    super.dispose();
  }

  bool get _ownedByGroup => widget.groupId != null;

  bool get _editing => widget.editing != null;

  /// 이 하루만 고치는 중이면 반복을 못 바꾼다 — 하루짜리 행이 될 것이라 규칙이 없다.
  bool get _canSetRepeat => !widget.onlyThisDay;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.lilacTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: T.textFaint, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_editing ? '일정 고치기' : '일정 적기',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
            if (widget.onlyThisDay) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_date.month}월 ${_date.day}일 하루만 바꿉니다',
                    style: const TextStyle(fontSize: 12, color: T.textSecondary)),
              ),
            ],
            const SizedBox(height: 12),

            _label('종류'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ScheduleKind.values)
                _chip(k.label, _kind == k, () => setState(() => _kind = k)),
            ]),
            const SizedBox(height: 14),

            _label('제목'),
            TextField(
              controller: _title,
              maxLength: ScheduleRepository.maxTitleLength,
              decoration: const InputDecoration(
                hintText: '예) 보리 광견병 접종',
                counterText: '',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            _label('언제'),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickDate,
                  child: Text('${_date.month}월 ${_date.day}일'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickTime,
                  // 시각은 **없어도 되는 값**이라 기본이 "하루 종일" 이다.
                  child: Text(_time == null ? '하루 종일' : Schedule.formatTime(_time!)),
                ),
              ),
              if (_time != null)
                IconButton(
                  tooltip: '시각 지우기',
                  onPressed: () => setState(() => _time = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ]),
            const SizedBox(height: 14),

            if (_canSetRepeat) ...[
              _label('반복'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in ScheduleRepeat.values)
                  _chip(r.label, _repeat == r, () => setState(() {
                        _repeat = r;
                        if (!r.repeats) _repeatUntil = null;
                      })),
              ]),
              if (_repeat.repeats) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickRepeatUntil,
                      // 끝이 없어도 된다 — 조회가 기간으로 잘리므로 안전하다.
                      child: Text(_repeatUntil == null
                          ? '끝없이'
                          : '${_repeatUntil!.month}월 ${_repeatUntil!.day}일까지'),
                    ),
                  ),
                  if (_repeatUntil != null)
                    IconButton(
                      tooltip: '종료일 지우기',
                      onPressed: () => setState(() => _repeatUntil = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ]),
              ],
              const SizedBox(height: 14),
            ],

            if (widget.pets.isNotEmpty) ...[
              _label('아이'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_ownedByGroup)
                  _chip('안 정함', _dogId == null, () => setState(() => _dogId = null)),
                for (final p in widget.pets)
                  _chip(p.name, _dogId == p.serverId,
                      () => setState(() => _dogId = p.serverId)),
              ]),
              const SizedBox(height: 14),
            ],

            // 가족이 없으면 담당을 물을 사람이 없다 — 칸 자체를 안 그린다.
            if (widget.members.isNotEmpty) ...[
              _label('담당'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip('안 정함', _assignee == null, () => setState(() => _assignee = null)),
                for (final m in widget.members)
                  _chip(m.nickname, _assignee == m.userId,
                      () => setState(() => _assignee = m.userId)),
              ]),
              const SizedBox(height: 14),
            ],

            _label('메모'),
            TextField(
              controller: _memo,
              maxLines: 2,
              maxLength: ScheduleRepository.maxMemoLength,
              decoration: const InputDecoration(
                hintText: '안 적어도 돼요',
                counterText: '',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _ownedByGroup ? '우리 가족이 함께 봅니다' : '이 일정은 나만 봅니다',
                style: const TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ),
            const SizedBox(height: 4),
            // 알림이 기기 로컬이라는 한계를 여기서 말한다(#420). 안 말하면 사용자는
            // "아빠 담당" 이라고 적어 두고 아빠가 알림을 받을 거라고 믿는다.
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('알림은 이 기기에만 옵니다 — 설정에서 켤 수 있어요',
                  style: TextStyle(fontSize: 12, color: T.textMuted)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD1495B))),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: T.sigEnd),
                child: Text(_saving ? '저장 중…' : '저장'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: T.textSecondary)),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? T.sigEnd : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? T.sigEnd : T.cardBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : T.textSecondary)),
        ),
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickRepeatUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil ?? _date,
      firstDate: _date,
      lastDate: DateTime(_date.year + 5),
    );
    if (picked != null) {
      setState(() => _repeatUntil = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '제목을 적어 주세요');
      return;
    }
    if (!_ownedByGroup && _dogId == null) {
      setState(() => _error = '아이를 골라 주세요');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final editing = widget.editing;
      final saved = editing == null
          ? await widget.repository.create(
              ownerKind:
                  _ownedByGroup ? ScheduleOwnerKind.group : ScheduleOwnerKind.dog,
              ownerRef: _ownedByGroup ? widget.groupId! : _dogId!,
              kind: _kind,
              title: title,
              onDate: _date,
              dogId: _dogId,
              memo: _memo.text.trim(),
              atTime: _time,
              assignee: _assignee,
              repeatKind: _repeat,
              repeatUntil: _repeatUntil,
            )
          : await widget.repository.update(
              scheduleId: editing.id,
              version: editing.version,
              kind: _kind,
              title: title,
              onDate: _date,
              dogId: _dogId,
              memo: _memo.text.trim(),
              atTime: _time,
              assignee: _assignee,
              // 이 하루만 고치는 중이면 반복을 안 보낸다 — 하루짜리 행이 될 것이라
              // 규칙이 없다. 안 보내면 서버가 안 바꾼다.
              repeatKind: _canSetRepeat ? _repeat : null,
              repeatUntil: _canSetRepeat ? _repeatUntil : null,
              onlyDay: widget.onlyThisDay ? editing.onDate : null,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ScheduleFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e.kind) {
          ScheduleFailureKind.conflict =>
            '다른 분이 방금 고쳤어요. 닫고 다시 열어 주세요',
          ScheduleFailureKind.notFound => '이 아이나 가족의 일정은 만들 수 없어요',
          ScheduleFailureKind.invalid => e.message ?? '아직 만들 수 없는 일정이에요',
          _ => '연결이 불안정해요. 잠시 뒤 다시 해 주세요',
        };
      });
    }
  }
}

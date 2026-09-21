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
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/family_repository.dart';
import '../data/notification_route.dart';
import '../data/schedule_repository.dart';
import '../domain/pet.dart';
import '../domain/schedule.dart';
import '../domain/schedule_reminder.dart';
import '../theme/app_tokens.dart';
import '../theme/member_colors.dart';
import '../widgets/aurora.dart';
import '../widgets/dog_avatar.dart';
import '../widgets/form_kit.dart';
import 'login_screen.dart';

/// 목록을 무엇으로 거를까. `전체` 가 기본이다 — 달력의 기본이 합쳐 보기다.
class ScheduleFilter {
  /// `null` 이면 전부.
  final int? dogId;

  /// 가족 것만.
  final bool groupOnly;

  /// 담당이 나인 것만(#736). 서버에 묻지 않고 앱에서 거른다 — 목록 API 에 담당 조건이 없고,
  /// 이 달은 이미 다 받아 두었다.
  final bool mineOnly;

  const ScheduleFilter({this.dogId, this.groupOnly = false, this.mineOnly = false});

  static const all = ScheduleFilter();
  static const mine = ScheduleFilter(mineOnly: true);

  bool get isAll => dogId == null && !groupOnly && !mineOnly;
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

  /// 알림을 누르고 들어왔을 때 잠깐 물드는 줄(#420 후속). 1.4초 뒤에 스스로 꺼진다.
  int? _focusedId;
  Timer? _focusOff;
  static const Duration _focusFor = Duration(milliseconds: 1400);

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
    // 로그인 상태가 바뀌면 다시 읽는다 — 게스트로 열어 둔 탭이 로그인 뒤에도 안내를 들고
    // 있으면 안 된다(#680). 채팅 탭과 같은 자리다.
    AuthState.status.addListener(_onAuth);
    _load();
    // 알림이 가리킨 그 일정. 꺼져 있던 앱이 알림으로 떴으면 이미 와 있고(첫 프레임 뒤에 본다),
    // 앱이 떠 있는 동안 누른 것은 듣고 있다가 받는다.
    ScheduleFocusInbox.pending.addListener(_drainFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainFocus());
  }

  @override
  void dispose() {
    ScheduleFocusInbox.pending.removeListener(_drainFocus);
    AuthState.status.removeListener(_onAuth);
    _focusOff?.cancel();
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    // 누구인지가 바뀌었으니 가족도 다시 묻는다 — 게스트일 때는 묻지 않았다.
    _groupResolved = false;
    _load();
  }

  /// 알림이 말한 날로 옮기고 그 줄을 잠깐 물들인다.
  ///
  /// **달이 다르면 그 달을 다시 읽는다** — 이 화면은 한 달치만 들고 있어서(`_load`), 옮기기만 하면
  /// 그 날이 빈 날로 보인다. 물드는 것은 잠깐이다: 계속 칠해 두면 사용자가 그 줄을 "고른 것" 으로 읽는다.
  void _drainFocus() {
    if (!mounted) return;
    final focus = ScheduleFocusInbox.take();
    if (focus == null) return;

    final day = _dayOf(focus.onDate);
    final sameMonth = day.year == _month.year && day.month == _month.month;
    setState(() {
      _selected = day;
      if (!sameMonth) _month = DateTime(day.year, day.month);
      _focusedId = focus.scheduleId;
    });
    _focusOff?.cancel();
    _focusOff = Timer(_focusFor, () {
      if (mounted) setState(() => _focusedId = null);
    });
    if (!sameMonth) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    if (AuthState.hasNoToken) {
      // 게스트는 일정이 없는 게 아니라 계정이 없다. 서버를 부르지 않는다(#324 · #680) —
      // 부르면 가족·일정 둘 다 401 이고, 그것이 "불러오지 못했어요 · 다시 시도" 로 그려졌다.
      // 소셜 왕복 중에도 토큰은 없으므로 함께 막는다(#673): 그때 나간 401 이 세션 만료로
      // 번역되면서 로그인 화면이 통째로 사라졌다.
      setState(() {
        _items = const [];
        _failure = ScheduleFailureKind.unauthorized;
        _loading = false;
      });
      return;
    }

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
        // 담당이 있는 일정은 담당자 기기에서만 울린다(#734).
        myUserId: AuthState.user?.id,
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

  /// 갈래를 거친 이 달의 일정. "내 담당" 은 서버가 아니라 여기서 거른다(#736) — 목록 API 에
  /// 담당 조건이 없고, 이 달은 이미 다 받아 두었다. 알림 예약(`_refreshReminders`)은 `_items` 를
  /// 보므로 이 갈래에 흔들리지 않는다.
  List<Schedule> get _visible {
    final me = AuthState.user?.id;
    final base = _filter.mineOnly
        ? _items.where((s) => s.assignee != null && s.assignee!.userId == me)
        : _items;
    return base.toList()..sort(Schedule.compare);
  }

  List<Schedule> get _ofSelectedDay =>
      _visible.where((s) => s.isOn(_selected)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      // 홈·커뮤니티와 같은 결(#453) — 단색 바탕이 아니라 오라 위에 반투명 카드다.
      body: AuroraBackground(
        child: SafeArea(
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
                  // 아래 140 — 떠 있는 알약(66 + 여백)이 목록 끝을 덮지 않게.
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 140),
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
      ),
      // 떠 있는 + 는 없앴다(#453) — 빈 상태의 "일정 적기" 와 겹쳐 같은 일을 하는 버튼이 둘이었다.
      // 새로 적기는 머리말 오른쪽의 둥근 버튼 하나다(iOS 캘린더의 자리).
    );
  }

  // ─────────────────────── 머리말 ───────────────────────

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 16, 10),
        child: Row(children: [
          // 탭이면 뒤로 갈 곳이 없고, 어디선가 밀려 들어왔으면 뒤로 가는 길이 있어야 한다.
          if (Navigator.of(context).canPop())
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              tooltip: '뒤로',
              color: T.textSecondary,
            )
          else
            const SizedBox(width: 12),
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
          const SizedBox(width: 4),
          SigFab(icon: Icons.add_rounded, tooltip: '일정 추가', size: 38, onPressed: _openCreateSheet),
        ]),
      );

  Widget _filterChips() {
    final pets = kMyPets.value.where((p) => p.serverId != null).toList();
    // 아이 칩에는 그 아이의 사진(없으면 종 이모지)이 앞에 붙는다 — 홈·내 정보와 같은 사진(#448).
    Widget chip(String label, bool selected, VoidCallback onTap, {DogProfile? dog, Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? T.accent : T.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? T.accent : T.cardBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (dog != null) ...[
                  DogAvatar(dog: dog, size: 18, emojiSize: 18),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : T.textSecondary)),
              ]),
            ),
          ),
        );

    void pick(ScheduleFilter next) {
      setState(() => _filter = next);
      _load();
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('전체', _filter.isAll, () => pick(ScheduleFilter.all)),
          for (final pet in pets)
            chip(pet.name, _filter.dogId == pet.serverId,
                () => pick(ScheduleFilter(dogId: pet.serverId)), dog: pet),
          if (_groupId != null)
            chip('가족', _filter.groupOnly,
                () => pick(const ScheduleFilter(groupOnly: true))),
          // 담당이 나인 것만(#736) — 가족이 있고 내가 누군지 알 때만. 구글 캘린더의 "내 것만".
          if (_groupId != null && AuthState.user != null)
            chip('내 담당', _filter.mineOnly, () => pick(ScheduleFilter.mine),
                key: const Key('schedule-filter-mine')),
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

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
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
          // 1.0 — 예전 0.82 는 세로가 길어 달력이 화면 절반을 넘었다(#453).
          childAspectRatio: 1.0,
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
              color: isSelected ? T.accent : Colors.transparent,
              border: isToday && !isSelected
                  ? Border.all(color: T.accent, width: 1.4)
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
      // 로그인이 필요한 것은 "다시 시도" 로 풀리지 않는다 — 안내와 로그인 버튼이다(#680).
      if (_failure == ScheduleFailureKind.unauthorized) return _loginNotice();
      return _notice(
        _failure == ScheduleFailureKind.network
            ? '일정을 불러오지 못했어요'
            : '이 일정은 볼 수 없어요',
        // 권한이 없는 것(403)도 다시 눌러서 될 일이 아니라 버튼을 안 그린다.
        action: _failure == ScheduleFailureKind.forbidden ? null : '다시 시도',
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

  Widget _emptyState() => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
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
          SizedBox(
            width: 180,
            child: PrimaryButton(label: '일정 적기', onPressed: _openCreateSheet),
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

  /// 로그인 안내에 적는 이유. 로그인 화면에도 같은 말을 들고 간다.
  static const String _loginReason = '로그인하면 우리 가족 일정을 함께 봐요';

  /// 게스트·세션 만료의 안내(#680). "다시 시도" 를 안 그린다 — 눌러도 영원히 같다. 채팅 탭의
  /// 카드와 같은 모양이고 같은 곳(로그인 화면)으로 간다.
  Widget _loginNotice() => Container(
        key: const Key('schedule-login-notice'),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: T.cardBg,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.cardBorder),
        ),
        child: Column(children: [
          const Text('로그인이 필요해요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 4),
          const Text(_loginReason,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: T.textSecondary)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _goLogin,
            icon: const Icon(Icons.login_rounded, size: 17),
            label: const Text('로그인'),
          ),
        ]),
      );

  void _goLogin() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen(reason: _loginReason)),
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
    final crew = s.ownerKind == ScheduleOwnerKind.room;
    final memo = s.memo?.trim() ?? '';
    final parts = <String>[
      // 크루 일정은 그렇다고 말한다 — 내 아이 일정 사이에 "보리 봐 주기" 만 있으면 누구
      // 것인지 모른다(#417).
      if (crew) '크루',
      if (dog != null) dog,
      // 담당은 글자가 아니라 그 사람 색의 태그다 — 아래 _assigneeTag(#736).
      if (!s.isAllDay) Schedule.formatTime(s.atTime!),
      // 크루 일정은 시각 대신 **시간대를 메모에** 든다("오후 · 두 시간만") — 품앗이가 정하는
      // 것은 시각이 아니라서다. 안 적으면 그날 아침에 언제인지가 안 보인다.
      if (crew && memo.isNotEmpty) memo,
      // 되풀이하는 것은 그렇다고 말한다 — 안 적으면 "왜 매주 있지" 를 사용자가 푼다.
      if (s.repeats) s.repeatKind.label,
    ];
    final done = !s.status.isOpen;
    // 알림을 누르고 들어온 그 줄(#420 후속). 색 하나로만 말한다 — 화살표나 배지를 얹으면
    // 1.4초 뒤에 사라지는 것이 레이아웃을 흔든다.
    final focused = _focusedId == s.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditSheet(s),
      child: AnimatedContainer(
      key: Key('schedule-row-${s.id}'),
      duration: const Duration(milliseconds: 240),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: focused ? T.accentSoft : T.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? T.accent : T.cardBorder),
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
            if (parts.isNotEmpty || s.assignee != null)
              Row(children: [
                if (s.assignee != null) ...[
                  _assigneeTag(s),
                  if (parts.isNotEmpty) const SizedBox(width: 6),
                ],
                if (parts.isNotEmpty)
                  Flexible(
                    child: Text(parts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: T.textMuted)),
                  ),
              ]),
          ]),
        ),
        IconButton(
          onPressed: () => _toggle(s),
          tooltip: done ? '아직 안 함으로' : '완료로',
          icon: Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: done ? T.accent : T.textFaint,
          ),
        ),
      ]),
      ),
    );
  }

  /// 담당자 태그 — 사람마다 색(#736). 색은 가족 목록의 순서에서 온다. 목록에 없는 사람(크루
  /// 일정의 담당 · 가족을 아직 못 읽음)은 회색이다 — 없는 순서를 지어내지 않는다.
  Widget _assigneeTag(Schedule s) {
    final a = s.assignee!;
    final idx = _members.indexWhere((m) => m.userId == a.userId);
    final color = idx < 0 ? T.textMuted : memberColor(idx);
    return Container(
      key: Key('assignee-tag-${s.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(0x1F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('${a.nickname} 담당',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
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
      // 홈의 할 일 줄이 듣는다(#741). 지금은 셸이 탭마다 화면을 새로 만들어 그 줄이 살아
      // 있지 않을 수 있지만, 바꾼 쪽이 화면 구조를 알 필요는 없다 — 케어 카드와 같은 신호다.
      kScheduleRev.value++;
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
    }
    // 문구는 저장소가 든다(#741) — 홈의 케어 카드가 같은 실패에 같은 말을 해야 한다.
    // 401·403 의 말(#680)도 거기(`userMessage`)에 있다.
    _say(e.userMessage);
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
    // 돌아오는 것은 고친 [Schedule] 이거나, 지웠다는 표시([ScheduleDeleted])다.
    final result = await showModalBottomSheet<Object>(
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
    if (result == null || !mounted) return;
    if (result is ScheduleDeleted) {
      _say(onlyThisDay ? '${s.onDate.month}월 ${s.onDate.day}일은 건너뛰어요' : '지웠어요');
    }
    // 무엇이 바뀌었는지(규칙인지 하루인지) 화면이 스스로 셀 수 없다 — 다시 불러온다.
    await _load();
  }

  Future<void> _openCreateSheet() async {
    if (AuthState.hasNoToken) {
      // 게스트의 "+" 는 시트가 아니라 로그인이다 — 글쓰기·산책 시작과 같은 길(#680).
      _goLogin();
      return;
    }
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

/// 고치기 시트가 "지웠다" 고 돌려주는 표시. 고친 [Schedule] 과 같은 자리로 온다.
///
/// `null` 로 돌리면 "그냥 닫았다" 와 구별이 안 돼 화면이 다시 안 불러온다 — 지운 줄이
/// 목록에 남는다.
class ScheduleDeleted {
  const ScheduleDeleted();
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
    // 틀(손잡이 · 제목 · 여백)은 폼 부품의 것이다(#445).
    return SheetFrame(
      title: _editing ? '일정 고치기' : '일정 적기',
      subtitle: widget.onlyThisDay ? '${_date.month}월 ${_date.day}일 하루만 바꿉니다' : null,
      children: [
            _label('종류'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ScheduleKind.values)
                _chip(k.label, _kind == k, () => setState(() => _kind = k)),
            ]),
            const SizedBox(height: 14),

            _label('제목'),
            GlassField(
              controller: _title,
              hint: '예) 보리 광견병 접종',
              maxLength: ScheduleRepository.maxTitleLength,
            ),
            const SizedBox(height: 14),

            _label('언제'),
            Row(children: [
              Expanded(
                child: PickerButton(
                  icon: Icons.event_outlined,
                  label: '${_date.month}월 ${_date.day}일',
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickerButton(
                  icon: Icons.schedule_outlined,
                  // 시각은 **없어도 되는 값**이라 기본이 "하루 종일" 이다.
                  label: _time == null ? '하루 종일' : Schedule.formatTime(_time!),
                  onPressed: _pickTime,
                  onClear: _time == null ? null : () => setState(() => _time = null),
                  clearTooltip: '시각 지우기',
                ),
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
                PickerButton(
                  icon: Icons.event_repeat_outlined,
                  // 끝이 없어도 된다 — 조회가 기간으로 잘리므로 안전하다.
                  label: _repeatUntil == null
                      ? '끝없이'
                      : '${_repeatUntil!.month}월 ${_repeatUntil!.day}일까지',
                  onPressed: _pickRepeatUntil,
                  onClear: _repeatUntil == null ? null : () => setState(() => _repeatUntil = null),
                  clearTooltip: '종료일 지우기',
                ),
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
                // 사람 칩은 그 사람의 색으로 — 목록의 담당 태그와 같은 색이다(#736).
                for (final (i, m) in widget.members.indexed)
                  PillChip(
                      label: m.nickname,
                      selected: _assignee == m.userId,
                      color: memberColor(i),
                      onTap: () => setState(() => _assignee = m.userId)),
              ]),
              const SizedBox(height: 14),
            ],

            _label('메모'),
            GlassField(
              controller: _memo,
              hint: '안 적어도 돼요',
              maxLines: 2,
              maxLength: ScheduleRepository.maxMemoLength,
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
            // 알림이 누구에게 가는지 여기서 말한다(#420 · #734) — 담당이 있으면 담당자만,
            // 없으면 가족 모두. 안 말하면 사용자는 아무 말 없이 "아빠 담당" 이라고 적어 두고
            // 자기 폰이 왜 조용한지(또는 왜 울리는지) 모른다.
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('알림은 담당자에게만 · 담당이 없으면 가족 모두에게 — 설정에서 켤 수 있어요',
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
            PrimaryButton(
              label: _saving ? '저장 중…' : '저장',
              onPressed: _saving ? null : _save,
            ),
            // 지우기는 고칠 때만 — 새로 적는 시트에는 지울 것이 없다. 범위는 위에서 이미
            // 물었다("이 날만 / 앞으로 전부") — 여기서 또 묻지 않고 그 답을 따른다.
            if (_editing) ...[
              const SizedBox(height: 8),
              SecondaryButton(
                buttonKey: const Key('schedule-delete'),
                label: _deleteLabel,
                danger: true,
                onPressed: _saving ? null : _delete,
              ),
            ],
      ],
    );
  }

  String get _deleteLabel {
    if (widget.onlyThisDay) return '이 날만 건너뛰기';
    return widget.editing!.repeats ? '반복 전부 지우기' : '지우기';
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

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      PillChip(label: label, selected: selected, onTap: onTap);

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

  /// 지운다 — 되돌릴 수 없으니 한 번 묻는다.
  ///
  /// 범위는 [ScheduleSheet.onlyThisDay] 를 따른다: 펼친 하루를 "이 날만" 으로 열었으면
  /// **그 하루만 건너뛰고**(`?date=`, #421) 규칙은 남긴다. 그 밖에는 그 일정(규칙이면
  /// 규칙 전체)이 사라진다. 서버가 그 둘을 가른다 — 앱은 날짜를 붙이거나 안 붙일 뿐이다.
  Future<void> _delete() async {
    final editing = widget.editing!;
    final onlyDay = widget.onlyThisDay;
    final day = '${editing.onDate.month}월 ${editing.onDate.day}일';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        key: const Key('schedule-delete-confirm'),
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(onlyDay ? '$day만 건너뛸까요?' : '이 일정을 지울까요?',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
        content: Text(
          onlyDay
              ? '나머지 날은 그대로예요.'
              : editing.repeats
                  ? '반복 규칙과 앞으로의 날이 전부 사라져요. 되돌릴 수 없어요.'
                  : '되돌릴 수 없어요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(onlyDay ? '건너뛰기' : '지우기',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: SecondaryButton.dangerColor)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository
          .delete(editing.id, onlyDay: onlyDay ? editing.onDate : null);
      if (!mounted) return;
      Navigator.of(context).pop(const ScheduleDeleted());
    } on ScheduleFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e.kind) {
          ScheduleFailureKind.notFound => '이미 지워진 일정이에요. 닫고 다시 열어 주세요',
          ScheduleFailureKind.unauthorized => '로그인이 필요해요',
          ScheduleFailureKind.forbidden => '이 일정은 지울 수 없어요',
          _ => '연결이 불안정해요. 잠시 뒤 다시 해 주세요',
        };
      });
    }
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
          ScheduleFailureKind.unauthorized => '로그인이 필요해요',
          ScheduleFailureKind.forbidden => '이 일정은 고칠 수 없어요',
          _ => '연결이 불안정해요. 잠시 뒤 다시 해 주세요',
        };
      });
    }
  }
}

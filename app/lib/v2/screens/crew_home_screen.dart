// 크루 홈 — 이슈 #417. 서버는 PR #426.
//
// ## 돌아갈 때 무엇이 달라졌는지 알려 준다
//
// 참여·나가기·고치기·강퇴·넘기기·지우기가 전부 **목록을 바꾼다.** 그래서 `pop(true)` 로
// "달라졌다" 를 들고 나간다 — 목록이 그것을 보고 서버에 다시 묻는다. 앱이 지레짐작해서
// 목록을 고치면, 요청이 실패했을 때 화면이 거짓말을 한다. 품앗이는 목록을 안 바꾼다.
//
// ## 안 든 사람에게 보이는 것은 인원 수까지다
//
// 공개 크루는 안 든 사람도 본다(안 그러면 들어갈지 말지 정할 수가 없다). 그런데 서버가
// 그때 `members` 를 **빈 배열**로 준다 — 누가 있는지는 안에서만이다. 화면은 그 빈 배열을
// "아직 아무도 없다" 로 그리면 안 된다. 인원 수는 따로 오고 있다.
//
// 품앗이도 같은 선이다 — **든 사람에게만 묻는다.** 부탁에는 아이 이름과 "그날 집을 비운다"
// 가 적혀서 서버도 안 든 사람에게는 404 다.
//
// ## 방장 자리의 버튼은 하나다 — 혼자면 지우기, 둘 이상이면 넘기기
//
// 사람이 있을 때 지우기를 그리면 눌러도 409 다(남의 대화를 지우는 버튼은 없다, 서버 PR #428).
// 혼자일 때 넘기기를 그리면 넘길 사람이 없다. 그래도 판정은 서버가 한다 — 화면이 낡았으면
// (그 사이 누가 들어왔으면) 409 를 받고 다시 불러온다.
import 'package:flutter/material.dart';

import '../data/crew_repository.dart';
import '../data/invite_share.dart';
import '../domain/crew.dart';
import '../domain/crew_favor.dart';
import '../theme/app_tokens.dart';
import '../widgets/form_kit.dart';
import '../widgets/aurora.dart';
import '../widgets/crew_favor_sheet.dart';
import 'family_chat_screen.dart';

class CrewHomeScreen extends StatefulWidget {
  final int crewId;

  /// 목록이 쓰던 리포지토리를 그대로 받는다. 테스트도 여기로 가짜를 넣는다.
  final CrewRepository? repository;

  const CrewHomeScreen({super.key, required this.crewId, this.repository});

  @override
  State<CrewHomeScreen> createState() => _CrewHomeScreenState();
}

class _CrewHomeScreenState extends State<CrewHomeScreen> {
  late final CrewRepository _repo = widget.repository ?? CrewRepository();

  Crew? _crew;
  bool _loading = true;
  CrewFailure? _failure;

  /// 무언가 바뀌었나. 돌아갈 때 목록에 전한다 — 파일 머리말 참조.
  bool _changed = false;

  /// 지금 왕복 중인가. 두 번 눌러 두 번 들어가는 것을 막는다.
  bool _busy = false;

  /// 품앗이. **든 크루에서만** 받는다 — 파일 머리말 참조.
  List<CrewFavor> _favors = const [];
  bool _favorsLoading = false;
  CrewFailure? _favorsFailure;

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
    try {
      final crew = await _repo.detail(widget.crewId);
      if (!mounted) return;
      setState(() {
        _crew = crew;
        _loading = false;
      });
      if (crew.mine) await _loadFavors();
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _loading = false;
      });
    }
  }

  /// 부탁 목록만 다시 받는다. 크루 자체는 그대로다 — 맡기·무르기는 인원을 안 바꾼다.
  Future<void> _loadFavors() async {
    setState(() {
      _favorsLoading = true;
      _favorsFailure = null;
    });
    try {
      final favors = await _repo.favors(widget.crewId);
      if (!mounted) return;
      setState(() {
        _favors = favors;
        _favorsLoading = false;
      });
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _favorsFailure = e;
        _favorsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = _crew;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: T.bgTop,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: T.textPrimary,
          title: Text(crew?.name ?? '크루',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          actions: [
            if (crew != null && crew.owner)
              IconButton(
                key: const Key('crew-edit'),
                tooltip: '크루 고치기',
                onPressed: _busy ? null : () => _openEdit(crew),
                icon: const Icon(Icons.tune_rounded, size: 20),
              ),
          ],
        ),
        body: AuroraBackground(child: SafeArea(child: _body())),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_failure case final failure?) {
      // 초대 크루를 안 든 사람이 열면 404 다 — "권한이 없어요" 로 고쳐 말하지 않는다.
      // 그렇게 말하면 서버가 감춘 존재를 화면이 도로 알려 주는 셈이다.
      final gone = failure.kind == CrewFailureKind.notFound;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(gone ? '크루를 찾을 수 없어요' : '크루를 불러오지 못했어요',
                key: const Key('crew-home-failure'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
            const SizedBox(height: 6),
            Text(gone ? '지워졌거나 초대를 받아야 볼 수 있어요' : '잠시 뒤 다시 시도해 주세요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: T.textMuted)),
            if (!gone) ...[
              const SizedBox(height: 14),
              _wideButton('다시 시도', _load, filled: false),
            ],
          ]),
        ),
      );
    }

    final crew = _crew!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _summaryCard(crew),
        const SizedBox(height: 14),
        if (crew.mine) ...[
          _wideButton('대화방으로 가기', () => _openRoom(crew)),
          const SizedBox(height: 10),
          if (crew.owner) ...[
            _wideButton('초대 코드 보내기', () => _shareInvite(crew), filled: false),
            const SizedBox(height: 10),
          ],
          _membersCard(crew),
          const SizedBox(height: 14),
          _favorsCard(),
          const SizedBox(height: 14),
          if (!crew.owner)
            _wideButton('크루 나가기', _leave, filled: false, danger: true)
          else
            ..._ownerActions(crew),
        ] else ...[
          _joinCard(crew),
        ],
      ],
    );
  }

  Widget _summaryCard(Crew crew) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF57C98A).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_walk_rounded,
                size: 21, color: Color(0xFF3FA873)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(crew.name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: T.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${crew.visibility.label} · ${crew.headcount}명',
                      key: const Key('crew-home-headcount'),
                      style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
                ]),
          ),
        ]),
        if (crew.intro case final intro?) ...[
          const SizedBox(height: 12),
          Text(intro,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.45, color: T.textSecondary)),
        ],
      ]),
    );
  }

  /// 멤버 목록. **안 든 사람에게는 이 카드 자체가 없다** — 파일 머리말 참조.
  Widget _membersCard(Crew crew) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('멤버',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 10),
        for (final member in crew.members) _memberRow(crew, member),
      ]),
    );
  }

  Widget _memberRow(Crew crew, CrewMember member) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: T.sigEnd.withValues(alpha: 0.18),
          child: Text(
            member.nickname.isEmpty ? '?' : member.nickname.characters.first,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: T.textPrimary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(member.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
        ),
        if (member.isOwner)
          const Text('방장',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF3FA873)))
        // 방장은 자기를 못 내보낸다 — 서버도 400 이다. 버튼을 안 그리는 것이 그 말을
        // 화면에서 먼저 하는 것이다.
        else if (crew.owner)
          IconButton(
            key: Key('crew-kick-${member.userId}'),
            tooltip: '${member.nickname} 내보내기',
            onPressed: _busy ? null : () => _kick(crew, member),
            icon: const Icon(Icons.person_remove_outlined, size: 18, color: T.textMuted),
          ),
      ]),
    );
  }

  /// 안 든 공개 크루에서 보이는 카드.
  Widget _joinCard(Crew crew) {
    final full = crew.isFull;
    return GlassCard(
      child: Column(children: [
        Text(
          full ? '지금은 정원이 찼어요' : '이 크루에 참여할 수 있어요',
          key: const Key('crew-join-headline'),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          full ? '자리가 나면 들어갈 수 있어요' : '들어가면 대화방에도 함께 들어가요',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: T.textMuted),
        ),
        const SizedBox(height: 14),
        _wideButton(full ? '정원이 찼어요' : '참여하기', full ? null : _join),
      ]),
    );
  }

  /// 품앗이 카드. **든 사람에게만** 있다 — 파일 머리말 참조.
  Widget _favorsCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('품앗이',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
          TextButton.icon(
            key: const Key('crew-favor-add'),
            onPressed: _busy ? null : _openFavorSheet,
            style: TextButton.styleFrom(
              foregroundColor: T.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('부탁하기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ]),
        const Text('아이 맡길 일이 생기면 여기에 적어요 · 맡으면 크루 달력에 남아요',
            style: TextStyle(fontSize: 11.5, color: T.textMuted, height: 1.3)),
        const SizedBox(height: 10),
        if (_favorsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (_favorsFailure != null)
          Row(children: [
            const Expanded(
              child: Text('부탁을 불러오지 못했어요',
                  key: Key('crew-favors-failure'),
                  style: TextStyle(fontSize: 12.5, color: T.textSecondary)),
            ),
            TextButton(onPressed: _loadFavors, child: const Text('다시 시도')),
          ])
        else if (_favors.isEmpty)
          const Text('아직 부탁이 없어요',
              key: Key('crew-favors-empty'),
              style: TextStyle(fontSize: 12.5, color: T.textSecondary))
        else
          for (final favor in _favors) _favorRow(favor),
      ]),
    );
  }

  Widget _favorRow(CrewFavor favor) {
    final who =
        favor.mine ? '내 부탁' : '${favor.askedBy?.nickname ?? '알 수 없음'} 님의 부탁';
    final String? state = favor.takenByMe
        ? '내가 맡았어요 · 달력에 남았어요'
        : favor.isOpen
            ? null
            : '${favor.takenBy?.nickname ?? '알 수 없음'} 님이 맡았어요';

    // 버튼은 하나다. 올린 사람은 거둬들이기, 맡은 사람은 무르기, 그 밖의 사람은 열려 있을
    // 때만 "제가 할게요" — 남이 맡은 것에는 버튼이 없다. 서버의 권한과 같은 모양이다.
    final Widget action;
    if (favor.mine) {
      action = _smallButton('거둬들이기',
          key: Key('crew-favor-cancel-${favor.id}'),
          onTap: () => _cancelFavor(favor),
          danger: true);
    } else if (favor.takenByMe) {
      action = _smallButton('무르기',
          key: Key('crew-favor-release-${favor.id}'), onTap: () => _releaseFavor(favor));
    } else if (favor.isOpen) {
      action = _smallButton('제가 할게요',
          key: Key('crew-favor-take-${favor.id}'),
          onTap: () => _takeFavor(favor),
          filled: true);
    } else {
      action = const SizedBox.shrink();
    }

    return Container(
      key: Key('crew-favor-${favor.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(favor.whenLabel,
                key: Key('crew-favor-when-${favor.id}'),
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            if (favor.detailLabel case final detail?) ...[
              const SizedBox(height: 2),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: T.textSecondary)),
            ],
            const SizedBox(height: 3),
            Text([who, if (state != null) state].join(' · '),
                key: Key('crew-favor-state-${favor.id}'),
                style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        action,
      ]),
    );
  }

  Widget _smallButton(
    String label, {
    required Key key,
    required VoidCallback onTap,
    bool filled = false,
    bool danger = false,
  }) {
    final enabled = !_busy;
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: filled && enabled ? T.sig : null,
          color: filled
              ? (enabled ? null : T.textFaint.withValues(alpha: 0.4))
              : T.surface,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: filled
                    ? Colors.white
                    : (danger ? const Color(0xFFD2604F) : T.textSecondary))),
      ),
    );
  }

  /// 방장 자리의 버튼. **혼자면 지우기, 둘 이상이면 넘기기**다 — 파일 머리말 참조.
  List<Widget> _ownerActions(Crew crew) {
    final alone = crew.members.every((m) => m.isOwner);
    if (alone) {
      return [
        _wideButton('크루 지우기', _delete, filled: false, danger: true),
        const SizedBox(height: 8),
        _ownerNote('아직 나 혼자예요. 지우면 대화방과 품앗이도 함께 사라져요.'),
      ];
    }
    return [
      _wideButton('방장 넘기기', () => _transfer(crew), filled: false),
      const SizedBox(height: 8),
      _ownerNote('방장은 크루를 나갈 수 없어요. 넘기면 나갈 수 있고, 혼자 남으면 지울 수 있어요.'),
    ];
  }

  /// 버튼만 두면 왜 하나뿐인지 아무도 모른다 — 한 줄이 그것을 말한다.
  Widget _ownerNote(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            key: const Key('crew-owner-note'),
            style: const TextStyle(fontSize: 12, color: T.textMuted, height: 1.35)),
      );

  Widget _wideButton(
    String label,
    VoidCallback? onTap, {
    bool filled = true,
    bool danger = false,
  }) {
    final enabled = onTap != null && !_busy;
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        key: Key('crew-action-$label'),
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: filled && enabled ? T.sig : null,
            color: filled
                ? (enabled ? null : T.textFaint.withValues(alpha: 0.4))
                : T.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: filled
                        ? Colors.white
                        : (danger ? const Color(0xFFD2604F) : T.textSecondary))),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── 동작 ───────────────────────────

  Future<void> _openRoom(Crew crew) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilyChatScreen(
        roomId: crew.roomId,
        title: crew.name,
        subtitle: '${crew.memberCount}명',
        isOwner: crew.owner,
      ),
    ));
    if (!mounted) return;
    // 방에서 내보냈을 수도 있다 — 인원이 달라졌는지 서버가 답하게 한다.
    await _load();
  }

  Future<void> _join() => _run(() async {
        final crew = await _repo.join(widget.crewId);
        if (!mounted) return;
        setState(() {
          _crew = crew;
          _changed = true;
        });
        _say('크루에 들어왔어요');
      });

  Future<void> _leave() async {
    final ok = await _confirm(
      title: '크루를 나갈까요',
      body: '대화방에서도 함께 나가요. 다시 들어올 수는 있어요.',
      action: '나가기',
    );
    if (ok != true) return;
    await _run(() async {
      await _repo.leave(widget.crewId);
      if (!mounted) return;
      _changed = true;
      Navigator.of(context).pop(true);
    });
  }

  Future<void> _kick(Crew crew, CrewMember member) async {
    final ok = await _confirm(
      title: '${member.nickname} 님을 내보낼까요',
      body: '내보내면 이 크루에 다시 들어올 수 없어요.',
      action: '내보내기',
    );
    if (ok != true) return;
    await _run(() async {
      await _repo.kick(widget.crewId, member.userId);
      if (!mounted) return;
      _changed = true;
      await _load();
      if (!mounted) return;
      _say('${member.nickname} 님을 내보냈어요');
    });
  }

  Future<void> _shareInvite(Crew crew) => _run(() async {
        final invite = await _repo.issueInvite(crew.roomId);
        if (!mounted) return;
        await InviteShare.sendCrew(invite.code, crew.name);
      });

  Future<void> _openEdit(Crew crew) async {
    final edited = await showModalBottomSheet<Crew>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CrewEditSheet(crew: crew, repository: _repo),
    );
    if (!mounted || edited == null) return;
    setState(() {
      _crew = edited;
      _changed = true;
    });
  }

  // ─────────────────────────── 품앗이 ───────────────────────────

  Future<void> _openFavorSheet() async {
    final posted = await showCrewFavorSheet(
      context,
      repository: _repo,
      crewId: widget.crewId,
    );
    if (!mounted || posted == null) return;
    // 서버에 다시 안 묻는다 — 올린 것을 날짜 순서에 끼워 넣으면 같은 목록이다.
    setState(() => _favors = [..._favors, posted]..sort(CrewFavor.compare));
    _say('부탁을 올렸어요');
  }

  Future<void> _takeFavor(CrewFavor favor) => _run(() async {
        try {
          final taken = await _repo.takeFavor(widget.crewId, favor.id);
          if (!mounted) return;
          setState(() => _favors = _replaceFavor(taken));
          _say('맡았어요 · 크루 달력에 남겼어요');
        } on CrewFailure catch (e) {
          // 그 사이 남이 맡았거나 거둬들여졌다 — 화면이 낡은 것이다. 목록을 다시 받는다.
          if (e.kind == CrewFailureKind.notFound) {
            if (!mounted) return;
            await _loadFavors();
            if (mounted) _say('그 부탁은 이미 사라졌어요. 목록을 새로 받았어요.');
            return;
          }
          if (e.kind == CrewFailureKind.taken && mounted) await _loadFavors();
          rethrow;
        }
      });

  Future<void> _releaseFavor(CrewFavor favor) async {
    final ok = await _confirm(
      title: '맡은 것을 무를까요',
      body: '부탁이 다시 열리고, 내 달력의 줄은 사라져요.',
      action: '무르기',
    );
    if (ok != true) return;
    await _run(() async {
      final released = await _repo.releaseFavor(widget.crewId, favor.id);
      if (!mounted) return;
      setState(() => _favors = _replaceFavor(released));
      _say('물렀어요 · 부탁이 다시 열렸어요');
    });
  }

  Future<void> _cancelFavor(CrewFavor favor) async {
    final taker = favor.takenBy?.nickname;
    final ok = await _confirm(
      title: '부탁을 거둬들일까요',
      body: favor.isOpen
          ? '목록에서 사라져요. 다시 올릴 수는 있어요.'
          : '${taker == null ? '맡은 분이 있어요' : '$taker 님이 맡았어요'}. '
              '거둬들이면 그분 달력에서도 사라져요.',
      action: '거둬들이기',
    );
    if (ok != true) return;
    await _run(() async {
      await _repo.cancelFavor(widget.crewId, favor.id);
      if (!mounted) return;
      setState(() => _favors = _favors.where((f) => f.id != favor.id).toList());
      _say('부탁을 거둬들였어요');
    });
  }

  List<CrewFavor> _replaceFavor(CrewFavor updated) =>
      [for (final f in _favors) f.id == updated.id ? updated : f];

  // ─────────────────────────── 방장 넘기기 · 크루 지우기 ───────────────────────────

  Future<void> _transfer(Crew crew) async {
    final others = crew.members.where((m) => !m.isOwner).toList();
    final target = await showDialog<CrewMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: T.bgTop,
        title: const Text('누구에게 넘길까요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('넘기면 나는 일반 멤버가 돼요 — 고치기·초대·내보내기를 못 하고, 대신 나갈 수 있어요.',
                style: TextStyle(fontSize: 12.5, color: T.textMuted, height: 1.35)),
          ),
          for (final member in others)
            SimpleDialogOption(
              key: Key('crew-transfer-${member.userId}'),
              onPressed: () => Navigator.of(ctx).pop(member),
              child: Text(member.nickname,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final ok = await _confirm(
      title: '${target.nickname} 님에게 넘길까요',
      body: '방장 자리는 하나예요. 되돌리려면 그분이 다시 넘겨 줘야 해요.',
      action: '넘기기',
    );
    if (ok != true) return;
    await _run(() async {
      final updated = await _repo.transferOwner(widget.crewId, target.userId);
      if (!mounted) return;
      setState(() {
        _crew = updated;
        _changed = true;
      });
      _say('${target.nickname} 님이 방장이 됐어요');
    });
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: '크루를 지울까요',
      body: '대화방과 품앗이, 달력에 남긴 줄까지 함께 사라져요. 되돌릴 수 없어요.',
      action: '지우기',
    );
    if (ok != true) return;
    await _run(() async {
      try {
        await _repo.delete(widget.crewId);
      } on CrewFailure catch (e) {
        // 그 사이 누가 들어왔다 — 화면이 낡은 것이다. 다시 받으면 넘기기 버튼으로 바뀐다.
        if (e.kind == CrewFailureKind.notAlone && mounted) await _load();
        rethrow;
      }
      if (!mounted) return;
      _changed = true;
      Navigator.of(context).pop(true);
    });
  }

  /// 한 번에 하나만. 실패는 **종류대로** 말한다.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on CrewFailure catch (e) {
      if (!mounted) return;
      _say(_reason(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _reason(CrewFailure failure) => switch (failure.kind) {
        CrewFailureKind.full => '정원이 찼어요. 자리가 나면 들어갈 수 있어요.',
        CrewFailureKind.inviteDead => '코드가 만료됐어요. 다시 발급해 주세요.',
        CrewFailureKind.forbidden => failure.message ?? '권한이 없어요.',
        CrewFailureKind.notFound => '크루를 찾을 수 없어요.',
        CrewFailureKind.taken => '이미 다른 분이 맡았어요. 목록을 새로 받았어요.',
        CrewFailureKind.notAlone => '다른 멤버가 남아 있어요. 방장을 넘기고 나가는 길이 있어요.',
        CrewFailureKind.network => '연결이 끊겼어요. 잠시 뒤 다시 시도해 주세요.',
        CrewFailureKind.invalid => failure.message ?? '요청을 처리하지 못했어요.',
      };

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.bgTop,
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(body, style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('그만두기')),
          FilledButton(
            key: const Key('crew-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// 방장이 고치는 시트.
///
/// **만들기 시트를 재사용하지 않는다.** 고치기는 "안 바꾼다" 가 기본이라 빈 칸의 뜻이
/// 반대다 — 만들기에서 빈 소개는 "없다" 이고, 고치기에서 빈 소개는 "지운다" 다. 한
/// 위젯에 조건문으로 섞으면 그 차이가 숨는다(서버의 `CrewInput`/`CrewPatch` 와 같은 판단).
class _CrewEditSheet extends StatefulWidget {
  final Crew crew;
  final CrewRepository repository;

  const _CrewEditSheet({required this.crew, required this.repository});

  @override
  State<_CrewEditSheet> createState() => _CrewEditSheetState();
}

class _CrewEditSheetState extends State<_CrewEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.crew.name);
  late final TextEditingController _intro =
      TextEditingController(text: widget.crew.intro ?? '');

  late CrewVisibility _visibility = widget.crew.visibility;
  late int _capacity = widget.crew.capacity;

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // **바뀐 것만 보낸다.** 전부 보내면 그 사이 남이 고친 값을 되돌린다 — 지금은
      // 방장 혼자 고치지만, 넘기기가 생기는 날 방장이 둘이 되는 순간이 있다.
      final crew = await widget.repository.edit(
        widget.crew.id,
        name: name == widget.crew.name ? null : name,
        // 빈 문자열은 "지운다" 다 — `null`(안 바꾼다)과 다르다.
        intro: _intro.text.trim() == (widget.crew.intro ?? '')
            ? null
            : _intro.text.trim(),
        visibility: _visibility == widget.crew.visibility ? null : _visibility,
        capacity: _capacity == widget.crew.capacity ? null : _capacity,
      );
      if (!mounted) return;
      Navigator.of(context).pop(crew);
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message ?? '고치지 못했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 틀·입력칸·버튼은 폼 부품이다(#445) — 만들기 시트와 같은 결.
    return SheetFrame(
      title: '크루 고치기',
      subtitle: '이름을 바꾸면 대화방 이름도 함께 바뀌어요',
      children: [
              const FormLabel('이름'),
              GlassField(
                key: const Key('crew-edit-name'),
                controller: _name,
                hint: '이름',
                maxLength: CrewRepository.maxNameLength,
              ),
              const SizedBox(height: 12),
              const FormLabel('소개 (비우면 지워져요)'),
              GlassField(
                key: const Key('crew-edit-intro'),
                controller: _intro,
                hint: '소개',
                maxLength: CrewRepository.maxIntroLength,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              Row(children: [
                for (final v in CrewVisibility.values) ...[
                  Expanded(
                    child: GestureDetector(
                      key: Key('crew-edit-visibility-${v.wire}'),
                      onTap: () => setState(() => _visibility = v),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _visibility == v
                              ? T.accentLine
                              : T.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _visibility == v ? T.accent : Colors.transparent),
                        ),
                        child: Center(
                          child: Text(v.label,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: _visibility == v ? T.textPrimary : T.textMuted)),
                        ),
                      ),
                    ),
                  ),
                  if (v != CrewVisibility.values.last) const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Text('정원',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: T.textSecondary)),
                const Spacer(),
                IconButton(
                  onPressed: _capacity > CrewRepository.minCapacity
                      ? () => setState(() => _capacity--)
                      : null,
                  icon: const Icon(Icons.remove_rounded, size: 20),
                ),
                SizedBox(
                  width: 56,
                  child: Center(
                    child: Text('$_capacity명',
                        key: const Key('crew-edit-capacity'),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: T.textPrimary)),
                  ),
                ),
                IconButton(
                  onPressed: _capacity < CrewRepository.maxCapacity
                      ? () => setState(() => _capacity++)
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
              ]),
              // 이미 든 사람보다 작게 줄이는 것을 막지 않는다 — 서버도 막지 않는다.
              // 줄인 값은 "더 안 받는다" 는 뜻으로 그대로 성립한다.
              if (_capacity < widget.crew.memberCount)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('지금 인원보다 적어요 — 이미 든 사람은 그대로 있어요',
                        key: Key('crew-edit-capacity-note'),
                        style: TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ),
                ),
              if (_error case final message?) ...[
                const SizedBox(height: 10),
                Text(message,
                    key: const Key('crew-edit-error'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD2604F))),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                buttonKey: const Key('crew-edit-submit'),
                label: _sending ? '저장 중…' : '저장',
                onPressed: _sending ? null : _submit,
              ),
      ],
    );
  }
}

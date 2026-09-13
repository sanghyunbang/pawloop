// 크루 홈 — 이슈 #417. 서버는 PR #426.
//
// ## 돌아갈 때 무엇이 달라졌는지 알려 준다
//
// 이 화면에서 하는 일 넷(참여·나가기·고치기·강퇴)이 전부 **목록을 바꾼다.** 그래서
// `pop(true)` 로 "달라졌다" 를 들고 나간다 — 목록이 그것을 보고 서버에 다시 묻는다.
// 앱이 지레짐작해서 목록을 고치면, 요청이 실패했을 때 화면이 거짓말을 한다.
//
// ## 안 든 사람에게 보이는 것은 인원 수까지다
//
// 공개 크루는 안 든 사람도 본다(안 그러면 들어갈지 말지 정할 수가 없다). 그런데 서버가
// 그때 `members` 를 **빈 배열**로 준다 — 누가 있는지는 안에서만이다. 화면은 그 빈 배열을
// "아직 아무도 없다" 로 그리면 안 된다. 인원 수는 따로 오고 있다.
import 'package:flutter/material.dart';

import '../data/crew_repository.dart';
import '../data/invite_share.dart';
import '../domain/crew.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
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
    } on CrewFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _loading = false;
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
          if (!crew.owner)
            _wideButton('크루 나가기', _leave, filled: false, danger: true)
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '방장은 크루를 나갈 수 없어요. 넘기기·지우기는 아직 준비 중이에요.',
                key: Key('crew-owner-cannot-leave'),
                style: TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ),
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
                : Colors.white.withValues(alpha: 0.7),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.bgTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('크루 고치기',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary)),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('이름을 바꾸면 대화방 이름도 함께 바뀌어요',
                    style: TextStyle(fontSize: 12.5, color: T.textMuted)),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('crew-edit-name'),
                controller: _name,
                maxLength: CrewRepository.maxNameLength,
                decoration: _decoration('이름'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crew-edit-intro'),
                controller: _intro,
                maxLength: CrewRepository.maxIntroLength,
                maxLines: 2,
                decoration: _decoration('소개 (비우면 지워져요)'),
              ),
              const SizedBox(height: 12),
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
                              ? T.sigEnd.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _visibility == v ? T.sigEnd : Colors.transparent),
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
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('crew-edit-submit'),
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: T.sigEnd,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_sending ? '저장 중…' : '저장',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        counterText: '',
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.75),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
}

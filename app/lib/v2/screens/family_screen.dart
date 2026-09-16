import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import 'invite_join_screen.dart';
import '../data/family_repository.dart';
import '../data/invite_share.dart';
import '../widgets/aurora.dart';
import '../widgets/today_care_card.dart';
import 'care_items_screen.dart';
import 'family_chat_screen.dart';

/// 우리 가족 — 가족 구성원 · 오늘의 케어 공유 · 산책 주의사항 · 가족 채팅.
/// (물·밥·산책을 가족이 함께 챙기는 케어 허브)
///
/// ## 무엇이 서버이고 무엇이 아직 아닌가 (이슈 #76)
///
/// **서버:** 구성원(`GET /api/groups/me`) · 오늘의 케어(`GET|POST .../care-logs`) ·
/// 산책 주의사항(`GET|PUT .../walk-notes`) · 초대코드(`POST /api/chat/rooms/{id}/invites`).
///
/// **아직 아닌 것:** "오늘 걸은 거리". 서버가 거리를 주는 경로가 없다 — 한동안 "연동 전"
/// 카드로 두었는데 미완성이 사용자에게 보였다(#329). 지금은 카드가 없고, 거리 공유는 위치
/// 사업 제약(#235)이 풀린 뒤 넣는다. 이 화면이 실제로 하는 말("아빠가 2.4km 걸었다")이
/// 사실이 아니면 다른 칸의 사실까지 의심받는다.
///
/// 예전에는 이 화면 전체가 `pet.dart` 의 로컬 더미(`kCareToday`·`kFamilyMembers`·
/// `kWalkNotes`·`kFamilyInviteCode`)였다. 그 상태에서는 엄마가 밥을 줘도 아빠 화면에는
/// 아무 일도 일어나지 않는다 — 이 이슈가 막으려는 사고가 정확히 거기서 생긴다.
/// 특히 `kFamilyInviteCode`(`PAW-2481`)는 **아무도 그 코드로 들어올 수 없는 문자열**이라,
/// 구성원만 서버로 바꾸고 코드를 더미로 두면 전보다 더 나쁜 화면이 된다.
class FamilyScreen extends StatefulWidget {
  /// 테스트가 가짜 저장소를 꽂는 자리. 운영 경로에서는 null 이다 —
  /// [TodayCareCard] 가 같은 구멍을 같은 이유로 이미 갖고 있다.
  ///
  /// 이 구멍이 없는 동안 이 화면(구성원 카드·주의사항 왕복·초대 시트·상태 카드)은
  /// 어느 앱 테스트에도 잡히지 않았다.
  final FamilyRepository? repository;

  /// 그룹이 없으면 이름 시트를 바로 연다 — 홈 케어 카드의 "만들기" 가 한 단계가 되게(#329).
  final bool openCreate;

  const FamilyScreen({super.key, this.repository, this.openCreate = false});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();

  FamilyGroupSummary? _group;
  WalkNoteSheet _note = WalkNoteSheet.empty;
  FamilyFailureKind? _failure;
  bool _loading = true;

  /// 주의사항을 보내는 중. 같은 순간에 두 번 보내면 나중 것이 앞 것을 덮는다.
  bool _savingNote = false;

  /// [FamilyScreen.openCreate] 로 시트를 한 번 열었는가 — 닫고 다시 읽을 때 또 뜨면 못 나간다.
  bool _createOffered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 그룹과 주의사항을 함께 읽는다. 케어 기록은 [TodayCareCard] 가 스스로 읽는다 —
  /// 그 카드가 홈에서도 같은 일을 하므로 읽는 코드가 두 벌이 되지 않게 한 곳에 둔다.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final group = await _repo.myGroup();
      final note = await _repo.walkNote(group.id);
      if (!mounted) return;
      setState(() {
        _group = group;
        _note = note;
        _loading = false;
      });
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.kind;
        _loading = false;
      });
      // 홈 "만들기" 로 왔는데 그룹이 없으면 이름 시트를 바로 연다(#329).
      if (e.kind == FamilyFailureKind.noGroup && widget.openCreate && !_createOffered) {
        _createOffered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCreateSheet();
        });
      }
    }
  }

  /// 주의사항 목록을 통째로 보낸다 — 서버가 아는 것은 메모 **한 장**이다.
  ///
  /// 낙관적으로 화면부터 바꾸지 않는다. 실패했을 때 화면에는 지워졌는데 서버에는 남아
  /// 있는 상태가 되고, 다음 진입에서 되살아나는 항목을 사용자가 유령으로 본다.
  Future<void> _saveNotes(List<String> lines) async {
    final group = _group;
    if (group == null || _savingNote) return;

    final body = WalkNoteSheet.fromLines(lines);
    // 왕복 전에 막는다. 서버도 400 으로 거절하지만(CareSharingIntegrationTest
    // .anOverlongWalkNote_is400), 그때 사용자가 보는 것은 실패한 뒤의 문구다 —
    // 여기서 걸러야 "왜 안 되는지" 를 누르기 전에 알려줄 수 있다.
    if (body.length > FamilyRepository.maxTextLength) {
      _toast(FamilyFailure.messageFor(FamilyFailureKind.invalid));
      return;
    }

    setState(() => _savingNote = true);
    try {
      final saved = await _repo.replaceWalkNote(group.id, body);
      if (!mounted) return;
      setState(() {
        _note = saved;
        _savingNote = false;
      });
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() => _savingNote = false);
      _toast(e.message);
    }
  }

  /// 실패 문구 한 줄. [FamilyFailure.messageFor] 가 만든 것을 그대로 띄운다 —
  /// 화면이 문구를 따로 적으면 같은 실패가 자리마다 다른 말을 한다.
  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // 케어/주의사항 공용 삭제 확인 다이얼로그.
  Future<bool> _confirmDelete(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('삭제할까요?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
        content: Text("'$what' 항목이 가족 모두에게서 삭제돼요.",
            style: const TextStyle(fontSize: 13.5, color: T.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFFF6B7E))),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            // 헤더 (me_screen 패턴)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: T.cardBorder),
                    ),
                    child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('우리 가족',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(22, 6, 22, MediaQuery.of(context).padding.bottom + 24),
                children: [
                  if (_loading || _failure != null) ...[
                    _statusCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_group != null) ...[
                    _membersCard(),
                    const SizedBox(height: 16),
                    // 홈과 **같은 위젯**이다. 두 화면이 같은 데이터를 그리는데 코드가 둘이면
                    // 확인 문구가 한쪽에만 생기는 날이 온다.
                    TodayCareCard(repository: widget.repository),
                    // 위 4 · 아래 20 이다. 둘을 10 · 16 으로 뒀더니 링크가 위아래 카드
                    // **한가운데** 떠서 어느 카드에 딸린 줄인지 안 보였다(에뮬레이터 실측).
                    // 가까이 있는 것끼리 한 덩이로 읽힌다 — 그 차이를 벌린다.
                    const SizedBox(height: 4),
                    if (_group case final group?) _careItemsLink(group.id),
                    const SizedBox(height: 20),
                    _walkNotesCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_group case final group?) _chatBanner(group.roomId),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ───────────── 로딩 · 실패 ─────────────
  //
  // 빈 화면으로 그리지 않는다. "가족이 아무것도 안 했다" 와 "서버에 못 닿았다" 와
  // "아직 가족이 없다" 는 사용자가 해야 할 일이 전부 다르다.
  Widget _statusCard() {
    if (_loading) {
      return const GlassCard(
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: T.warmText)),
          SizedBox(width: 10),
          Text('가족 정보를 불러오는 중', style: TextStyle(fontSize: 13.5, color: T.textSecondary)),
        ]),
      );
    }

    final failure = _failure!;
    final noGroup = failure == FamilyFailureKind.noGroup;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(noGroup ? Icons.group_add_rounded : Icons.cloud_off_rounded,
              size: 18, color: T.warmText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(FamilyFailure.messageFor(failure),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          noGroup
              ? '가족 그룹을 만들면 물·밥·산책을 함께 챙길 수 있어요'
              : '연결이 되면 오늘의 케어와 주의사항을 다시 불러올게요',
          style: const TextStyle(fontSize: 12.5, color: T.textMuted),
        ),
        const SizedBox(height: 12),
        if (noGroup) ...[
          // 여기가 비어 있던 자리다(#196). 로드맵은 M2.5 를 "앱 그룹 생성 경로만 남음" 이라
          // 적어 뒀는데, 그룹이 없는 사람에게는 만들 길도 참여할 길도 화면에 없었다 —
          // 서버는 POST /api/groups 를 진작 갖고 있었다.
          GestureDetector(
            onTap: _openCreateSheet,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(13)),
              child: const Text('가족 그룹 만들기',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          // 만드는 쪽만 있으면 혼자 쓰는 그룹이 된다(#196 의 3번). 참여는 이미
          // `InviteJoinScreen` 이 하고 있었는데 채팅 목록에서만 갈 수 있었다.
          GestureDetector(
            onTap: _openJoin,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: T.line),
              ),
              child: const Text('초대 코드로 참여하기',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: T.textSecondary)),
            ),
          ),
        ] else
          GestureDetector(
            onTap: _load,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(13)),
              child: const Text('다시 시도',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
      ]),
    );
  }

  /// 아바타 색. 서버는 색을 주지 않으므로 **참여 순서로** 고정한다 — 매번 랜덤이면
  /// 같은 사람이 화면을 열 때마다 다른 색이 되어 얼굴 대신 쓰는 표식이 되지 못한다.
  static const List<Color> _memberColors = [
    T.warmMid,
    Color(0xFF57C98A),
    Color(0xFF5B8DEF),
    T.accent,
    Color(0xFFEFA13C),
    T.warmEnd,
  ];

  Color _colorOf(int index) => _memberColors[index % _memberColors.length];

  // ───────────── 가족 구성원 ─────────────
  Widget _membersCard() {
    final members = _group?.members ?? const <FamilyMemberSummary>[];

    Widget member(int index, FamilyMemberSummary m) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _colorOf(index)),
              child: Text(m.nickname.isEmpty ? '?' : m.nickname.characters.first,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 7),
            Text(m.nickname,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            const SizedBox(height: 2),
            // OWNER/MEMBER 는 chat_room_member.role 그대로다. 화면에서만 우리말로 옮긴다.
            Text(m.isOwner ? '방장' : '가족',
                style: const TextStyle(fontSize: 11, color: T.textMuted)),
          ]),
        );

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('가족 구성원',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (int i = 0; i < members.length; i++) member(i, members[i]),
            GestureDetector(
              onTap: _openInviteSheet,
              behavior: HitTestBehavior.opaque,
              child: Column(children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: T.surface,
                    border: Border.all(color: T.warmStart.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: const Icon(Icons.add, size: 24, color: T.warmText),
                ),
                const SizedBox(height: 7),
                const Text('초대',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  // ───────────── 만들기 · 참여 (#196) ─────────────

  /// 그룹 이름을 받아 만든다.
  ///
  /// 이름을 묻는 이유는 그 값이 **방 이름도 되기 때문**이다(서버가 같은 문자열로
  /// `chat_room` 을 연다). 기본값을 넣어 두고 그대로 눌러도 되게 한다 — 대부분은
  /// 이름을 고민하려고 이 화면에 온 것이 아니다.
  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _CreateGroupSheet(repo: _repo),
    );
    if (!mounted || created != true) return;

    await _load();
    if (!mounted) return;
    // 만들자마자 초대 코드를 보여 준다. 혼자 있는 그룹은 아무 일도 안 한다 —
    // 가족을 부르는 것이 이 기능의 목적이다.
    await _openInviteSheet();
  }

  /// 초대 코드로 참여한다. 성공하면 그룹이 생겼으므로 다시 부른다.
  Future<void> _openJoin() async {
    final joined = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const InviteJoinScreen()));
    if (!mounted || joined != true) return;
    await _load();
  }

  // ───────────── 초대 ─────────────
  //
  // 예전에는 상수 하나(`kFamilyInviteCode = 'PAW-2481'`)를 보여 줬다. 그 코드로는
  // **아무도 들어올 수 없다** — 초대는 `chat_room_invite` 행이고 만료·사용횟수·회수를
  // 가진다(ADR-0011). 구성원 목록만 서버로 바꾸고 코드를 더미로 두면, 사용자는 진짜처럼
  // 보이는 코드를 가족에게 보내고 가족은 조용히 실패한다.
  //
  // 발급은 **방장만** 할 수 있다(403). 그 판정은 서버가 하고 여기서 미리 흉내내지 않는다 —
  // 두 곳이 판정하면 한쪽이 낡는다.
  Future<void> _openInviteSheet() async {
    final group = _group;
    if (group == null) return;

    FamilyInvite? invite;
    String? error;
    try {
      invite = await _repo.issueInvite(group.roomId);
    } on FamilyFailure catch (e) {
      error = e.kind == FamilyFailureKind.forbidden
          ? '초대코드는 방장만 발급할 수 있어요'
          : e.message;
    }
    // await 뒤의 첫 문장에서 가른다 — 이 State 가 사라졌으면 아무것도 하지 않는다.
    if (!mounted) return;

    if (invite == null || invite.code.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? '초대코드를 만들지 못했어요')));
      return;
    }
    _showInviteSheet(invite);
  }

  void _showInviteSheet(FamilyInvite invite) {
    final code = invite.code;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 18),
          const Text('가족 초대',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: T.warmStart.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: T.warmStart.withValues(alpha: 0.35)),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: T.warmText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 주 버튼은 공유 — 복사 → 앱 전환 → 붙여넣기 세 단계가 한 번이 된다(#329).
          GestureDetector(
            onTap: () => _shareInvite(sheetCtx, code),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: _warm,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: T.warmEnd.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('공유하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _copyInvite(sheetCtx, code),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: T.line),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.copy_rounded, size: 16, color: T.textSecondary),
                SizedBox(width: 6),
                Text('코드 복사',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textSecondary)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // 사실만 쓴다 — 만료·횟수는 발급 응답의 값이다(#329). "누를 때마다 새 코드가 하나 더
          // 생겨요" 는 사용자가 알아야 할 사실이 아니라 불안이었다. 재발급이 이전 코드를
          // 죽이지 않는 것(#75)은 그대로다 — 그래서 이 시트에 "재발급" 버튼이 없다.
          Text(inviteFactLine(expiresAt: invite.expiresAt?.toLocal(), maxUses: invite.maxUses),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
        ]),
      ),
    );
  }

  /// OS 공유 시트로 초대 문장을 보낸다. 못 열면(플러그인 없음·공유할 앱 없음) 복사로 대신한다.
  Future<void> _shareInvite(BuildContext sheetCtx, String code) async {
    Navigator.pop(sheetCtx);
    try {
      await InviteShare.send(code);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유 시트를 못 열어 코드를 복사했어요'), duration: Duration(milliseconds: 2000)),
      );
    }
  }

  void _copyInvite(BuildContext sheetCtx, String code) {
    Clipboard.setData(ClipboardData(text: code));
    Navigator.pop(sheetCtx);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대 코드가 복사되었어요'), duration: Duration(milliseconds: 1800)),
    );
  }

  // "오늘 걸은 거리" 카드는 없다(#329). 서버가 거리를 주는 경로가 없어 "연동 전" 이라고 적어
  // 두었는데, 미완성이 사용자에게 보였다. 거리 공유(위치정보 제3자 제공 동의 포함)는
  // 위치 사업 제약(#235)이 풀린 뒤 다시 넣는다.

  // ───────────── 산책 주의사항 (가족 누구나 추가/삭제) ─────────────
  //
  // **서버가 아는 것은 메모 한 장**이다(`walk_note`, 그룹당 한 장). 줄 단위 목록으로
  // 그리는 것은 이 화면의 표현이고, 추가·삭제는 편집된 전체 본문을 PUT 한다.
  //
  // 목록을 1:N 표로 두지 않은 이유는 `docs/03-database/schema.md §16` 에 있다 — 전량
  // 교체로 다루면 PUT 때마다 행이 새로 생겨 "누가 고쳤는지" 가 아무것도 가리키지 않는다.
  Widget _walkNotesCard() {
    final lines = _note.lines;

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.report_gmailerrorred_rounded, size: 18, color: T.warmText),
          SizedBox(width: 7),
          Text('산책 주의사항',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 9),
            child: Text('아직 주의사항이 없어요 · 가족과 공유할 메모를 남겨보세요',
                style: TextStyle(fontSize: 13, color: T.textMuted)),
          )
        else
          for (int i = 0; i < lines.length; i++)
            GestureDetector(
              onLongPress: _savingNote ? null : () => _removeNoteAt(i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: T.warmStart),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(lines[i],
                        style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary)),
                  ),
                  // "…" 메뉴 — 길게 누르기는 남기되 보이는 문이 하나 있어야 한다(#329).
                  GestureDetector(
                    onTap: _savingNote ? null : () => _openNoteMenu(i),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8, top: 1),
                      child: Icon(Icons.more_horiz_rounded, size: 18, color: T.textMuted),
                    ),
                  ),
                ]),
              ),
            ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _savingNote ? null : _openAddNoteSheet,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: T.warmStart.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: T.warmStart.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.add_rounded, size: 18, color: T.warmText),
              SizedBox(width: 5),
              Text('주의사항 추가',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.warmText)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _note.updatedByName == null || _note.updatedByName!.isEmpty
              ? '주의사항은 가족 모두에게 보여요'
              : '주의사항은 가족 모두에게 보여요 · 마지막 수정 ${_note.updatedByName}',
          style: const TextStyle(fontSize: 11.5, color: T.textMuted),
        ),
      ]),
    );
  }

  /// 한 줄을 지운다 — 확인을 받고, 남은 줄 전체를 다시 보낸다.
  /// 주의사항 한 줄의 "…" 메뉴. 지우기는 [_removeNoteAt] 이 한 번 더 묻는다 — 가족 모두에게서
  /// 사라지는 일이다.
  Future<void> _openNoteMenu(int index) async {
    final lines = _note.lines;
    if (index >= lines.length) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(lines[index],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: T.textMuted)),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(sheetCtx, 'delete'),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B7E)),
                SizedBox(width: 12),
                Text('지우기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFFF6B7E))),
              ]),
            ),
          ),
        ]),
      ),
    );
    if (!mounted || action != 'delete') return;
    await _removeNoteAt(index);
  }

  Future<void> _removeNoteAt(int index) async {
    final lines = _note.lines;
    if (index >= lines.length) return;

    final ok = await _confirmDelete(lines[index]);
    // await 뒤의 첫 문장에서 가른다. 시트가 떠 있는 동안 화면이 사라졌으면
    // setState 가 던진다 — 분석기가 잡는 것은 BuildContext 뿐이라 여기는 손으로 본다.
    if (!mounted || !ok) return;

    final remaining = [...lines]..removeAt(index);
    await _saveNotes(remaining);
  }

  /// 이번 줄에 더 쓸 수 있는 글자 수.
  ///
  /// 서버가 아는 것은 메모 **한 장**이라 한도는 줄이 아니라 **합계**에 걸린다. 이미 쓴
  /// 본문에 줄바꿈 한 칸을 더한 만큼이 예산에서 빠진다 — 그래야 화면이 허락한 길이가
  /// 그대로 저장된다.
  int get _noteBudget {
    final used = WalkNoteSheet.fromLines(_note.lines).length;
    return FamilyRepository.maxTextLength - (used == 0 ? 0 : used + 1);
  }

  // 주의사항 추가 시트.
  void _openAddNoteSheet() {
    // 남은 예산이 없으면 시트를 열지 않는다. 열어 두면 사용자가 글을 다 쓰고 나서야
    // 실패를 보게 되고, 그 사이에 쓴 것은 어디에도 안 남는다.
    if (_noteBudget <= 0) {
      _toast(FamilyFailure.messageFor(FamilyFailureKind.invalid));
      return;
    }
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            22, 12, 22, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 42, height: 5,
              decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('산책 주의사항 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: T.accentLine),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              minLines: 1,
              // 합계 한도 안에서 이번 줄이 쓸 수 있는 만큼. 카운터가 함께 뜨므로
              // 사용자가 남은 글자 수를 보면서 쓴다.
              maxLength: _noteBudget,
              style: const TextStyle(fontSize: 15, color: T.textPrimary),
              decoration: const InputDecoration(
                hintText: '예: 더운 날은 저녁 8시 이후에 나가기',
                hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(sheetCtx);
              // 시트를 먼저 닫고 보낸다 — 시트가 떠 있는 채로 스낵바를 띄우면 가려진다.
              _saveNotes([..._note.lines, text]);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(15)),
              child: const Text('추가하기',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  // ───────────── 할 일 고치기 ─────────────
  /// 카드 아래 한 줄 — 목록을 고치러 간다(#560 조각 3).
  ///
  /// **카드 헤더에 안 붙였다.** 거기는 이미 "우리 가족 ›" 이 폭을 나눠 쓰고 있어서, 글자를
  /// 키우면 제목 줄이 통째로 넘친다(#396 에서 실측으로 겪은 자리다). 카드 밖 한 줄이면 폭
  /// 경쟁이 없고, 무엇을 고치는지도 카드 바로 아래라 분명하다.
  Widget _careItemsLink(int groupId) {
    return GestureDetector(
      key: const Key('family-care-items-link'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CareItemsScreen(groupId: groupId)),
      ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          const Icon(Icons.tune_rounded, size: 16, color: T.textMuted),
          const SizedBox(width: 6),
          // Expanded 다 — Spacer 는 0 아래로 못 줄어들어 큰 글자에서 줄이 넘친다(#396).
          const Expanded(
            child: Text('할 일 고치기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ),
          const Icon(Icons.chevron_right, size: 16, color: T.textMuted),
        ]),
      ),
    );
  }

  // ───────────── 가족 채팅 배너 ─────────────
  /// 가족 채팅으로 가는 배너.
  ///
  /// [roomId] 는 서버가 그룹을 만들 때 함께 만든 방이다(ADR-0011). 그룹을 아직 못 읽었으면
  /// 이 배너를 안 그린다 — 방 번호 없이 채팅 화면을 열 수 없다.
  Widget _chatBanner(int roomId) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FamilyChatScreen(roomId: roomId, title: '가족 채팅')),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: T.warmEnd.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.chat_bubble_rounded, size: 21, color: Colors.white),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('가족 채팅',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 3),
              // 마지막 메시지를 여기 그리려면 요청이 하나 더 든다. 가짜 문장을 남기느니
              // 무엇을 하는 곳인지만 적는다 (#81).
              const Text(
                '가족과 나눈 대화 보기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: T.cardBg),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 20, color: Colors.white),
        ]),
      ),
    );
  }
}

/// 그룹 이름을 받는 시트 — 이슈 #196.
///
/// 화면이 아니라 시트인 이유는 필드가 하나뿐이라서다. `pet_registration_sheet` 가 같은
/// 모양이고, 실패도 스낵바가 아니라 **시트 안의 빨간 한 줄**로 말한다 — 폼에서 스낵바는
/// 입력칸을 가린다.
class _CreateGroupSheet extends StatefulWidget {
  final FamilyRepository repo;

  const _CreateGroupSheet({required this.repo});

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  /// **시트가 컨트롤러를 소유한다.** 부르는 쪽이 만들어 넘기고 pop 직후에 dispose 하면,
  /// 닫히는 애니메이션이 도는 동안 TextField 가 죽은 컨트롤러를 그린다 — 실제로 그렇게
  /// 짰다가 "A TextEditingController was used after being disposed" 를 봤다.
  final _name = TextEditingController(text: '우리 가족');

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '가족 이름을 적어 주세요');
      return;
    }
    // 서버가 50자에서 400 을 낸다. 여기서 막지 않으면 다 쓰고 누른 뒤에 알게 된다.
    if (name.length > FamilyRepository.maxGroupNameLength) {
      setState(() =>
          _error = '이름은 ${FamilyRepository.maxGroupNameLength}자까지 쓸 수 있어요');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.createGroup(name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.surfaceBright,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0x2E281E30),
                borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(height: 18),
          const Text('가족 그룹 만들기',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 6),
          const Text('이 이름이 가족 대화방 이름도 됩니다',
              style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: FamilyRepository.maxGroupNameLength,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 15, color: T.textPrimary),
            decoration: InputDecoration(
              hintText: '예) 보리네 가족',
              hintStyle: const TextStyle(fontSize: 14, color: T.textMuted),
              filled: true,
              fillColor: T.surface,
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: T.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: T.line),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFFD9534F))),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _saving ? null : _submit,
            child: Container(
              width: double.infinity,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: _saving
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [T.warmStart, T.warmEnd],
                      ),
                color: _saving ? T.textFaint : null,
                borderRadius: BorderRadius.circular(16),
              ),
              // 스피너가 아니라 문구를 바꾼다 — pet_registration_sheet 와 같은 모양이다.
              child: Text(_saving ? '만드는 중…' : '만들기',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

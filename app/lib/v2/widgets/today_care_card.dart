// lib/v2/widgets/today_care_card.dart
//
// "오늘의 케어" 카드 — 이슈 #76. 홈(`today_screen`)과 `family_screen` 이 같은 위젯을 쓴다.
//
// ## 이 카드가 막으려는 것
//
// 이중 급여(엄마가 밥을 줬는데 아빠가 또 준다)와 산책 누락(서로 상대가 다녀왔겠거니
// 한다). 둘 다 "오늘 누가 무엇을 했는지" 를 한 화면에 놓으면 사라진다 — 그래서 칸마다
// **누가·언제**를 함께 그린다. 체크 표시만 있으면 "내가 했나?" 를 지우지 못한다.
//
// ## 확인 문구는 앱이 만든다 (완료 조건 2)
//
// 서버는 같은 종류를 하루에 두 번 찍어도 **막지 않는다** — 두 번째가 실수인지 사실인지
// 서버는 모르고, 막으면 실제로 한 일이 기록에서 사라진다. 대신 "오늘 14:20 아빠가 밥을
// 줬습니다. 그래도 기록할까요?" 를 여기서 띄운다.
//
// 왜 앱인가: 확인 문구는 **쓰기 전에** 떠야 하므로 결국 읽기에서 나오고, 그 읽기는 이
// 카드가 이미 하고 있다(누가·언제를 그리려고). 응답에 "오늘 이미 있음" 필드를 더하면
// 같은 사실의 출처가 둘이 되고 둘이 어긋나는 날이 온다.
//
// ## 로딩·실패
//
// 네트워크가 없을 때 빈 카드를 그리면 "아무도 아무것도 안 했다" 로 읽힌다. 그건 이 화면이
// 낼 수 있는 가장 나쁜 거짓말이다 — 그걸 보고 밥을 한 번 더 준다. 그래서 로딩·실패·
// "가족 없음" 을 각각 다른 문구로 그린다.

import '../screens/login_screen.dart';
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/family_repository.dart';
import '../domain/pet.dart' show careIcon, CareType, kMyDog;
import '../theme/app_tokens.dart';
import 'aurora.dart';

/// 한 화면에서 기록하면 다른 화면의 카드도 다시 읽게 하는 신호.
///
/// 홈과 `family_screen` 이 같은 데이터를 그리는데 서로를 모른다. 값이 바뀌면 살아 있는
/// 카드가 전부 다시 읽는다 — `pet.dart` 의 `kCareRev` 가 로컬 더미에 대해 하던 일을
/// 서버 데이터에 대해 한다.
final ValueNotifier<int> kServerCareRev = ValueNotifier<int>(0);

/// 홈과 가족 화면이 함께 쓰는 "오늘의 케어" 카드.
class TodayCareCard extends StatefulWidget {
  /// 헤더 오른쪽의 "우리 가족 →" 을 눌렀을 때. 가족 화면 안에서는 null 이다.
  final VoidCallback? onOpenFamily;

  /// 테스트가 가짜 저장소를 꽂는 자리. 운영 경로에서는 null 이다.
  final FamilyRepository? repository;

  /// "내 기록인가" 를 가르는 id. 운영 경로에서는 null 이고 [AuthState.user] 를 읽는다 —
  /// 테스트가 로그인 상태를 만들지 않고도 본인/남 두 경우를 그리게 하려는 자리다.
  final int? myUserId;

  /// 가족이 없을 때 "만들기" 가 부른다. 없으면 [onOpenFamily] 로 간다 — 가족 화면에서
  /// 한 번 더 "가족 그룹 만들기" 를 눌러야 하는 두 단계였다(#329).
  final VoidCallback? onCreateFamily;

  const TodayCareCard({
    super.key,
    this.onOpenFamily,
    this.repository,
    this.myUserId,
    this.onCreateFamily,
  });

  @override
  State<TodayCareCard> createState() => _TodayCareCardState();
}

class _TodayCareCardState extends State<TodayCareCard> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();

  FamilyGroupSummary? _group;
  List<CareLogEntry> _logs = const [];
  FamilyFailureKind? _failure;
  bool _loading = true;

  /// 로그인한 적 없는 사람. 서버를 부르지 않는다(#324).
  bool _guest = false;

  /// 기록을 보내는 중인 종류. 같은 칸을 두 번 눌러 두 번 보내는 것을 막는다.
  ServerCareType? _sending;

  @override
  void initState() {
    super.initState();
    kServerCareRev.addListener(_reload);
    AuthState.status.addListener(_reload);
    // 고른 아이가 바뀌면 다시 읽는다(#563). 이 카드는 props 가 안 바뀌므로 홈이 다시
    // 그려도 State 가 그대로 살아 있다 — 신호를 직접 안 들으면 **앞 아이의 기록이 남는다.**
    kMyDog.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    kServerCareRev.removeListener(_reload);
    AuthState.status.removeListener(_reload);
    kMyDog.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    if (AuthState.isGuest) {
      // 게스트는 가족이 없는 게 아니라 아직 계정이 없다. 401 을 받아 "다시 로그인" 이라고
      // 말하는 대신 여기서 멈춘다(#324).
      setState(() {
        _guest = true;
        _loading = false;
      });
      return;
    }
    _guest = false;
    try {
      final group = _group ?? await _repo.myGroup();
      // **고른 아이의 기록만 센다**(#563). 이게 없으면 아이가 둘인 집에서 보리 이름 아래
      // 카드가 누리 밥까지 세고, "밥 2회" 가 보리한테 두 번인지 둘이 한 번씩인지 모르게 된다.
      final logs = await _repo.careLogs(group.id, dogId: kMyDog.value?.serverId);
      if (!mounted) return;
      setState(() {
        _group = group;
        _logs = logs;
        _loading = false;
      });
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.kind;
        _loading = false;
      });
    }
  }

  /// 그 종류의 **가장 최근** 기록. 없으면 null.
  ///
  /// 목록은 이른 것부터라 마지막이 최근이다. "오늘 이미 했다" 를 물을 때도, 칸에
  /// "누가·언제" 를 그릴 때도 이 하나를 쓴다 — 둘이 다른 행을 보면 확인 문구와 화면이
  /// 서로 다른 말을 한다.
  CareLogEntry? _latestOf(ServerCareType type) {
    CareLogEntry? found;
    for (final log in _logs) {
      if (log.type == type) found = log;
    }
    return found;
  }

  /// 오늘 그 종류가 몇 번인가.
  int _countOf(ServerCareType type) =>
      _logs.where((log) => log.type == type).length;

  /// 칸의 둘째 줄 — **한 줄에 하나만** 적는다. 셋 중 무엇을 적을지는 순서가 있다.
  ///
  /// 1. **아직 안 했으면** `아직`.
  /// 2. **두 번 이상이면 `N회`.** 하루 한 번이 아닌 것이 정상이다 — 밥 두 끼, 물 여러 번,
  ///    배변·마킹은 원래 세는 값이다(#549). 예전에는 배변·마킹만 횟수를 적어서, 밥을 두 번
  ///    준 날에도 칸은 마지막 사람 이름만 말했다. **두 번째를 막으려고 보는 자리인데 두 번
  ///    줬다는 사실이 화면에 없었다.**
  /// 3. **산책이고 거리가 있으면 거리.** 이름을 지우는 것이 아니다 — 남이 걸었으면 바로 위
  ///    한 줄이 "엄마가 아침에 1.2km 걸었어요" 로 이름을 말하고, 내가 걸었으면 이름이 나다.
  ///    거리는 이 칸 말고는 홈에 적을 자리가 없다.
  /// 4. 나머지는 **누가**. 물·밥은 두 번 주지 않으려고 보는 자리다.
  String _firstLine(ServerCareType type, CareLogEntry? done) {
    if (done == null) return '아직';
    final count = _countOf(type);
    if (count >= 2) return '$count회';
    if (type == ServerCareType.walk && (done.memo ?? '').isNotEmpty) return done.memo!;
    return done.doneByName;
  }

  /// 칸의 **셋째 줄**. 한 번이면 시각, 두 번 이상이면 **한 사람들**이다 — 이슈 #570.
  ///
  /// `2회` 만 있으면 둘이 한 번씩인지 한 사람이 두 번인지 화면이 구별을 못 한다. 이 앱의
  /// 목적이 업무 분담이라 그 구별이 곧 화면의 값어치다(#76). 두 번 이상일 때 시각을 빼는
  /// 이유는, 어느 시각을 적어도 나머지를 숨기기 때문이다 — 시각 전부는 "오늘 한 일" 이 적는다.
  ///
  /// 이름이 길면 `아빠 외 1` 로 접는다. 칸 폭이 좁아서(#326) 두 이름이 다 안 들어간다.
  String _secondLine(ServerCareType type, CareLogEntry? done) {
    if (done == null) return '';
    // **횟수로 가른다, 사람 수가 아니라.** 한 사람이 두 번 한 날도 첫 줄은 `2회` 인데,
    // 그때 시각 하나를 적으면 "누가" 가 화면에서 통째로 사라진다. `2회 · 아빠` 와
    // `2회 · 아빠·엄마` 가 달라 보여야 분담이 보인다.
    if (_countOf(type) < 2) return done.timeLabel;
    final names = _doersOf(type);
    if (names.length == 1) return names.first;
    // 둘을 다 적을 수 있으면 다 적는다. 칸이 좁아서(#326) 다섯 자가 한계다 —
    // `아빠·엄마` 는 들어가고 `아버지·할머니` 는 안 들어간다.
    final joined = names.join('·');
    return names.length == 2 && joined.characters.length <= 5
        ? joined
        : '${names.first} 외 ${names.length - 1}';
  }

  /// 오늘 이 칸을 누른 사람들. **중복 없이, 최근 순으로.**
  ///
  /// 최근 순인 이유: 한 번일 때 첫 줄이 **마지막에 한 사람**을 적는다. 둘 이상일 때
  /// 앞에 오는 이름이 달라지면 같은 칸이 상황에 따라 다른 기준으로 읽힌다.
  List<String> _doersOf(ServerCareType type) {
    final seen = <int>{};
    final names = <String>[];
    for (final log in _logs.reversed) {
      if (log.type != type) continue;
      if (!seen.add(log.doneByUserId)) continue;
      names.add(log.doneByName.isEmpty ? '누군가' : log.doneByName);
    }
    return names;
  }

  Future<void> _tap(ServerCareType type) async {
    final group = _group;
    if (group == null || _sending != null) return;

    final already = _latestOf(type);
    if (already != null) {
      final me = widget.myUserId ?? AuthState.user?.id;
      if (me != null && already.doneByUserId == me) {
        // 내 기록이 있는 칸을 다시 누른 것 — 대개 잘못 눌렀거나 무르고 싶은 것이다(#329).
        // 두 끼는 실제로 있으니 "한 번 더 기록" 도 같은 자리에서 고른다.
        final choice = await _askRetap(already);
        if (!mounted) return;
        switch (choice) {
          case _Retap.undo:
            await _delete(group, type, already);
            return;
          case _Retap.cancel:
            return;
          case _Retap.again:
            break;
        }
      } else {
        final ok = await _confirmDuplicate(already);
        // await 뒤의 첫 문장에서 가른다 — 이 State 가 사라졌으면 아무것도 하지 않는다.
        if (!mounted) return;
        if (!ok) return;
      }
    }

    setState(() => _sending = type);
    try {
      await _repo.recordCare(group.id, type, dogId: kMyDog.value?.serverId);
      if (!mounted) return;
      setState(() => _sending = null);
      // 다른 화면의 카드도 함께 다시 읽는다. 이 콜백이 자기 자신의 _load 도 부른다.
      kServerCareRev.value++;
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = null);
      _showMessage(e.message);
    }
  }

  /// "오늘 14:20 에 내가 남긴 밥 기록이에요" — 지우기 / 한 번 더 기록 / 취소.
  Future<_Retap> _askRetap(CareLogEntry mine) async {
    final answer = await showDialog<_Retap>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '이미 기록한 칸이에요',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          retapWarning(mine, _labelOf(mine.type)),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.cancel),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.again),
            child: const Text('한 번 더 기록',
                style: TextStyle(fontWeight: FontWeight.w700, color: T.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, _Retap.undo),
            child: const Text(
              '지우기',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? _Retap.cancel;
  }

  /// "오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?"
  Future<bool> _confirmDuplicate(CareLogEntry already) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '오늘 이미 기록이 있어요',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          duplicateWarning(already, _labelOf(already.type)),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              '그래도 기록',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// 칸을 길게 누르면 그 종류의 가장 최근 기록을 지운다 — **내 기록일 때만**(#209).
  ///
  /// 잘못 찍은 "밥 줌" 을 되돌리는 문이다. 서버는 두 번째 기록을 막지 않으므로(위 주석)
  /// 되돌릴 길이 없으면 사용자는 이 카드를 안 믿는다. 남의 기록은 서버도 403 으로 거절하지만
  /// 여기서 먼저 안내한다 — 지울 수 있으면 엄마가 실제로 다녀온 산책을 아빠가 "실수겠지"
  /// 하고 지우는, 이 카드가 막으려던 산책 누락이 그 자리에서 생긴다.
  Future<void> _deleteLatest(ServerCareType type) async {
    final group = _group;
    if (group == null || _sending != null) return;
    final latest = _latestOf(type);
    if (latest == null) return;

    final me = widget.myUserId ?? AuthState.user?.id;
    if (me == null || latest.doneByUserId != me) {
      _showMessage('내가 남긴 기록만 지울 수 있어요');
      return;
    }

    final ok = await _confirmDelete(latest);
    if (!mounted || !ok) return;
    await _delete(group, type, latest);
  }

  /// 확인은 끝난 뒤다 — 서버로 지우고 살아 있는 카드가 전부 다시 읽게 한다.
  Future<void> _delete(FamilyGroupSummary group, ServerCareType type, CareLogEntry latest) async {
    setState(() => _sending = type);
    try {
      await _repo.deleteCareLog(group.id, latest.id);
      if (!mounted) return;
      setState(() => _sending = null);
      kServerCareRev.value++;
    } on FamilyFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = null);
      _showMessage(e.message);
      // 벌써 지워진 기록이면 화면이 낡은 것이다 — 다시 읽으면 칸이 맞아진다.
      if (e.kind == FamilyFailureKind.gone) kServerCareRev.value++;
    }
  }

  /// "14:20 에 남긴 밥 기록을 지웁니다. 가족 화면에서도 사라져요."
  Future<bool> _confirmDelete(CareLogEntry entry) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '기록을 지울까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          deleteWarning(entry, _labelOf(entry.type)),
          style: const TextStyle(fontSize: 13.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              '지우기',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 그리기 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.diversity_1_rounded, size: 17, color: T.warmMid),
          const SizedBox(width: 6),
          // Spacer 대신 Expanded 다 — 글자를 키우면 제목이 자라는데 Spacer 는 0 아래로
          // 못 줄어들어 줄이 통째로 넘쳤다(360dp · 2.0배에서 38px, #396).
          const Expanded(
            child: Text('오늘의 케어',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
          ),
          if (widget.onOpenFamily != null)
            GestureDetector(
              onTap: widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text('우리 가족',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
                ),
                Icon(Icons.chevron_right, size: 16, color: T.warmText),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        _body(),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: T.warmText)),
          SizedBox(width: 8),
          // 아래 두 줄(게스트 · 실패)은 `Expanded` 인데 이 줄만 아니었다. 글자 2.0배 ·
          // 390dp 에서 16px 넘쳐 노란 줄무늬가 떴다 — 데이터가 오기 전 잠깐이라 아무도
          // 못 봤을 뿐이다(#561). `Flexible` 이라 가운데 정렬은 그대로다.
          Flexible(
            child: Text('오늘의 케어를 불러오는 중',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
        ]),
      );
    }

    if (_guest) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.login_rounded, size: 16, color: T.textMuted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('로그인하면 가족과 오늘의 케어를 나눠요',
                style: TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            behavior: HitTestBehavior.opaque,
            child: const Text('로그인',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
          ),
        ]),
      );
    }
    final failure = _failure;
    if (failure != null) {
      // 빈 카드로 그리지 않는다 — "아무도 아무것도 안 했다" 로 읽히고, 그걸 보고
      // 밥을 한 번 더 준다.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(
            failure == FamilyFailureKind.noGroup
                ? Icons.group_add_rounded
                : Icons.cloud_off_rounded,
            size: 16,
            color: T.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(FamilyFailure.messageFor(failure),
                style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
          ),
          // 가족이 없는 것은 오류가 아니라 **할 일**이다. 다시 시도는 아무것도 바꾸지
          // 않고, 그렇다고 아무 버튼도 안 주면 여기서 길이 끊긴다 — #196 이 그 상태였다.
          // 만들기 자체는 가족 화면이 한다. 여기서는 거기로 보낸다.
          if (failure == FamilyFailureKind.noGroup && widget.onOpenFamily != null)
            GestureDetector(
              onTap: widget.onCreateFamily ?? widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Text('만들기',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            )
          else if (failure != FamilyFailureKind.noGroup)
            GestureDetector(
              onTap: _load,
              behavior: HitTestBehavior.opaque,
              child: const Text('다시 시도',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: T.warmText)),
            ),
        ]),
      );
    }

    final alreadyWalked = _familyWalkLine();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 가족이 오늘 이미 걸었으면 한 줄로 말한다 (#343). **막지 않는다** — 하루 두 번
      // 걷는 집도 있다. 몰라서 두 번 나가는 것과 알고 두 번 나가는 것은 다르다.
      if (alreadyWalked != null) ...[
        Row(children: [
          const Icon(Icons.directions_walk_rounded, size: 15, color: T.warmText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(alreadyWalked,
                maxLines: 2,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText)),
          ),
        ]),
        const SizedBox(height: 9),
      ],
      for (int start = 0; start < kCareCardColumns.length; start += kCareCardColumnsPerRow) ...[
        if (start > 0) const SizedBox(height: 6),
        Row(children: [
          for (int i = 0; i < kCareCardColumnsPerRow; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: start + i < kCareCardColumns.length
                  ? _cell(kCareCardColumns[start + i])
                  // 마지막 줄의 빈 자리. 칸 폭을 두 줄에서 같게 두려고 자리만 잡는다.
                  : const SizedBox.shrink(),
            ),
          ],
        ]),
      ],
      ..._todayLog(),
    ]);
  }

  /// "오늘 한 일" 의 사람 칸 폭. 390dp 에서 `CrewOwner` 가 들어가는 값이다.
  static const double _logNameWidth = 78;

  /// 홈이 보여 줄 "오늘 한 일" 줄 수. 나머지는 헤더의 "우리 가족 →" 이 받는다.
  static const int homeLogLines = 3;

  /// **오늘 한 일** — 이슈 #570.
  ///
  /// 위의 칸 일곱은 "할 일" 이다. 각 칸은 **가장 최근 하나**만 말하므로, 아빠와 엄마가
  /// 밥을 한 번씩 준 날 그 칸은 `2회` 하나로 접힌다 — 둘이 한 번씩인지 한 사람이 두
  /// 번인지 알 수 없다. 이 앱의 목적이 업무 분담과 누락 방지라(#76) 그 구별이 곧 화면의
  /// 값어치다. 이 줄이 "한 일" 을 시간까지 펼친다.
  ///
  /// **누락은 위 칸이, 분담은 이 줄이 말한다.** 아무도 안 한 칸은 여기 안 나온다.
  ///
  /// 홈에서는 [homeLogLines] 줄까지만 보이고 나머지는 "그 밖 N개" 한 줄로 접힌다.
  /// 우리 가족 화면(`onOpenFamily == null`)에서는 전부 편다 — 그 화면이 "더 보기" 의
  /// 목적지라, 거기서도 접으면 갈 곳이 없다.
  List<Widget> _todayLog() {
    if (_logs.isEmpty) return const [];
    // **최근 순이다.** 목록은 이른 것부터 오는데(계약), 홈은 세 줄만 보이므로 이른 것부터
    // 자르면 **방금 누른 것이 안 보인다** — 누르고 나서 "기록됐나?" 를 확인할 수 없다.
    final newestFirst = _logs.reversed.toList();
    final full = widget.onOpenFamily == null;
    final shown = full ? newestFirst : newestFirst.take(homeLogLines).toList();
    final rest = newestFirst.length - shown.length;

    return [
      const SizedBox(height: 10),
      Container(height: 1, color: T.line),
      const SizedBox(height: 8),
      Row(children: [
        const Text('오늘 한 일',
            key: Key('care-log-title'),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: T.textMuted)),
        const SizedBox(width: 6),
        Text('${_logs.length}',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: T.textFaint)),
      ]),
      for (final log in shown) ...[
        const SizedBox(height: 5),
        _logLine(log),
      ],
      if (rest > 0) ...[
        const SizedBox(height: 5),
        Text('그 전에 $rest개',
            key: const Key('care-log-rest'),
            style: const TextStyle(fontSize: 11, color: T.textFaint)),
      ],
    ];
  }

  /// `10:39  아빠  물` — 시각 · 사람 · 무엇. 셋 다 왼쪽에 맞춘다.
  ///
  /// 사람 칸에 고정 폭을 주는 이유: 이름 길이가 제각각이라 그냥 두면 종류가 들쭉날쭉
  /// 앉는다. 훑을 때 눈이 따라가는 세로줄이 "무엇" 이라 그 줄이 흔들리면 안 읽힌다.
  ///
  /// 폭 [_logNameWidth] 는 에뮬레이터에서 보고 늘린 값이다 — 58 로 뒀더니 `CrewOwner`
  /// 가 `CrewOw…` 로 잘렸다. 그보다 긴 이름은 여전히 줄임표로 접는다(잘리는 편이
  /// 종류 줄이 흔들리는 것보다 낫다).
  Widget _logLine(CareLogEntry log) => Row(key: Key('care-log-${log.id}'), children: [
        SizedBox(
          width: 42,
          child: Text(log.timeLabel,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
        SizedBox(
          width: _logNameWidth,
          child: Text(log.doneByName.isEmpty ? '누군가' : log.doneByName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
        ),
        Expanded(
          child: Text(_labelOf(log.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: T.textSecondary)),
        ),
      ]);

  /// "아빠가 아침에 1.2km 걸었어요" — 이슈 #343.
  ///
  /// **남이 걸었을 때만이다.** 내가 걸은 것은 내가 안다 — 그 줄은 방금 한 일을 다시
  /// 읽어 주는 것이라 자리만 차지한다.
  ///
  /// 거리는 케어 로그의 메모에 실려 온다([WalkCareLink.kmLabel]). 없으면 거리 없이
  /// 적는다 — 옛 기록과 손으로 누른 산책 칸에는 메모가 없다.
  String? _familyWalkLine() {
    final latest = _latestOf(ServerCareType.walk);
    if (latest == null) return null;
    final me = widget.myUserId ?? AuthState.user?.id;
    if (me != null && latest.doneByUserId == me) return null;

    final name = latest.doneByName.isEmpty ? '누군가' : latest.doneByName;
    final distance = latest.memo == null || latest.memo!.isEmpty ? '' : '${latest.memo} ';
    return '$name${subjectParticle(name)} ${_partOfDay(latest.occurredAt)}에 $distance걸었어요';
  }

  static String _partOfDay(DateTime at) {
    if (at.hour < 6) return '새벽';
    if (at.hour < 12) return '아침';
    if (at.hour < 18) return '오후';
    return '저녁';
  }

  Widget _cell(ServerCareType type) {
    final done = _latestOf(type);
    final busy = _sending == type;

    return GestureDetector(
      onTap: busy ? null : () => _tap(type),
      // 길게 누르면 내 기록을 지운다(#209). 짧게 누르는 기록과 같은 칸이라 화면이 안 늘어난다.
      onLongPress: busy ? null : () => _deleteLatest(type),
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: Key('care-cell-${type.wire}'),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        // 완료한 칸은 **코랄 하나**다(#546). 종류마다 다른 색을 쓰던 자리인데, 칸마다
        // 아이콘과 이름이 이미 있어 색으로 가를 필요가 없고 — 색이 말하는 것은 종류가
        // 아니라 "했다" 다. 토큰 머리말이 정한 색 예외는 지도 카테고리색과 상태색뿐이다.
        decoration: BoxDecoration(
          color: done != null ? T.accentSoft : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done != null ? T.accentLine : T.surface),
        ),
        // **칸 일곱은 언제나 같은 크기다**(#561). 아이콘 한 줄 + 글 세 줄 — 상태가 무엇이든
        // 줄 수가 같아서, 한 번 누를 때마다 칸이 자라거나 이웃이 따라 움직이지 않는다.
        //
        // 예전에는 "아직"(세 줄) · 완료(네 줄) · 거리 붙은 산책(다섯 줄)이 섞여서 한 줄 안의
        // 칸들이 서로 다른 높이로 앉았다. 실측 [89, 75, 103, 89, 75, 89, 89] — 글자 2.0배에서는
        // 58px 이 벌어졌다.
        child: Column(children: [
          Icon(
            done != null ? Icons.check_circle_rounded : careIcon(_iconTypeOf(type)),
            size: 19,
            color: done != null ? T.accent : T.textMuted,
          ),
          const SizedBox(height: 4),
          Text(type.label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const SizedBox(height: 2),
          // 한 줄 "walker · 15:40" 은 다섯 칸 폭에서 "walker · 1…" 로 잘렸다(#326).
          // 둘째 줄과 셋째 줄로 나눈다 — 시각은 잘리지 않는다.
          Text(
            _firstLine(type, done),
            key: Key('care-line1-${type.wire}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: done == null ? T.textMuted : T.accent),
          ),
          // 아직 안 한 칸도 **빈 줄로 자리를 지킨다.** 이 줄을 없애면 누르는 순간 칸이
          // 한 줄만큼 자라고, 같은 줄의 이웃들이 통째로 밀린다.
          Text(
            _secondLine(type, done),
            key: Key('care-line2-${type.wire}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: T.accent),
          ),
        ]),
      ),
    );
  }

  /// 아이콘·색은 `pet.dart` 의 것을 그대로 쓴다 — 화면의 시각 언어가 갈리지 않게.
  /// 서버의 `vet`(병원)은 그쪽에 없어서 `etc` 로 떨어진다.
  ///
  /// 배변·마킹(#340)도 지금은 `etc` 다. **이 카드에 칸을 더할지는 아직 안 정했다** —
  /// 다섯 칸이 이미 좁아서(#326 의 라벨 잘림) 칸을 늘리면 두 줄로 바꾸는 문제가 함께 온다.
  /// 그때까지 그 기록은 산책 화면과 가족 목록에서 보인다. 여기서 값을 빠뜨리면 화면이
  /// 죽으므로 갈래는 지금 만들어 둔다.
  static CareType _iconTypeOf(ServerCareType type) => switch (type) {
        ServerCareType.water => CareType.water,
        ServerCareType.meal => CareType.meal,
        ServerCareType.walk => CareType.walk,
        ServerCareType.med => CareType.med,
        ServerCareType.vet => CareType.etc,
        ServerCareType.poop => CareType.etc,
        ServerCareType.pee => CareType.etc,
      };
}

/// 이 카드가 그리는 칸. **서버의 종류 전부가 아니다** — 목록을 여기 적는다(#340).
///
/// 예전에는 `ServerCareType.values` 를 그대로 돌렸다. 그러다 배변·마킹이 계약에 생기자
/// 칸이 다섯에서 일곱으로 **저절로** 늘었다. 화면에 무엇을 보일지는 계약이 아니라 이 화면이
/// 정할 일이라, 그때 목록을 여기로 옮기고 배변·마킹은 뺐다.
///
/// **2026-09-15 에 다시 넣었다**(#549 · 사장님 A). 빼 두는 동안 그 기록은 `care_log` 에
/// 쌓이기만 하고 앱 어디에서도 볼 수 없었다 — 산책 끝내기 시트가 "배변 1회" 라고 말해 놓고
/// 저장하면 사라졌다. 배변은 건강 신호라 "오늘 몇 번" 이 실제로 세는 값이다.
///
/// 순서는 그대로 두고 뒤에 붙였다. 한 줄에 일곱은 라벨이 잘리므로([kCareCardColumnsPerRow])
/// **넷에서 접는다** — 접는 자리를 옮기면 익숙한 순서가 바뀐다.
const List<ServerCareType> kCareCardColumns = [
  ServerCareType.water,
  ServerCareType.meal,
  ServerCareType.walk,
  ServerCareType.med,
  ServerCareType.vet,
  ServerCareType.poop,
  ServerCareType.pee,
];

/// 한 줄에 몇 칸인가. 390dp 에서 다섯도 이미 좁아 라벨이 잘렸다(#326) — 일곱은 두 줄이다.
/// 마지막 줄의 빈 자리는 **비워 둔다**: 줄마다 칸 폭이 달라지면 같은 카드가 두 벌처럼 보인다.
const int kCareCardColumnsPerRow = 4;

/// "14:20 에 남긴 밥 기록을 지웁니다. 가족 화면에서도 사라져요."
///
/// 무엇을 지우는지(종류·시각)를 문구에 넣는다 — 칸에는 가장 최근 하나만 보이므로 사용자가
/// 어느 기록인지 확인할 수 있어야 한다.
String deleteWarning(CareLogEntry entry, String what) =>
    '${entry.timeLabel} 에 남긴 $what 기록을 지웁니다. 가족 화면에서도 사라져요.';

/// "오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?"
///
/// 위젯 밖에 두는 이유: 이 문구가 완료 조건 2 그 자체라 **테스트가 직접 부를 수 있어야**
/// 한다. 위젯 안에 있으면 문구를 확인하는 방법이 화면을 띄우는 것뿐이다.
String duplicateWarning(CareLogEntry already, String what) {
  // 직접 만든 항목에는 종류가 없다(#560) — 그때는 칸 이름을 그대로 넣는다.
  // "양치를 했습니다" 가 "양치 기록을 남겼습니다" 보다 읽히지만, 이름이 무엇일지 모르므로
  // 조사를 붙이지 않는 쪽을 고른다 — '약' 과 '양치' 는 붙는 조사가 다르다.
  if (already.type == null) {
    return '오늘 ${already.timeLabel} 에 ${already.doneByName}님이 $what 기록을 남겼습니다.\n'
        '그래도 기록할까요?';
  }
  final phrase = switch (already.type!) {
    ServerCareType.water => '물을 갈아줬습니다',
    ServerCareType.meal => '밥을 줬습니다',
    ServerCareType.walk => '산책을 다녀왔습니다',
    ServerCareType.med => '약을 줬습니다',
    ServerCareType.vet => '병원에 다녀왔습니다',
    // 산책 중 한 탭으로 들어오는 것들(#340). 이 문구는 "그래도 기록할까요?" 앞에 붙는데,
    // 배변·마킹은 하루에 여러 번이 정상이라 중복 경고를 띄울 자리가 아니다 — 그래도
    // 값이 빠지면 화면이 죽으므로 문장은 만들어 둔다.
    ServerCareType.poop => '배변을 기록했습니다',
    ServerCareType.pee => '마킹을 기록했습니다',
  };
  final name = already.doneByName.isEmpty ? '누군가' : already.doneByName;
  return '오늘 ${already.timeLabel} $name${subjectParticle(name)} $phrase. 그래도 기록할까요?';
}

/// 주격 조사 — 받침이 있으면 `이`, 없으면 `가`.
///
/// "아빠가" 와 "지훈이가" 를 한 문장 틀로 만들려면 이게 필요하다. 늘 `가` 로 쓰면
/// "지훈가" 가 되고, 늘 `님이` 로 피하면 가족끼리 부르는 말투가 아니게 된다.
///
/// 한글 음절은 `0xAC00 + (초성×588) + (중성×28) + 종성` 이라 종성 유무가
/// `(code - 0xAC00) % 28` 로 나온다. 한글이 아닌 이름(영문·이모지)은 `가` 로 둔다.
String subjectParticle(String name) {
  if (name.isEmpty) return '가';
  final code = name.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) return '가';
  return (code - 0xAC00) % 28 == 0 ? '가' : '이';
}

/// 칸의 이름 — 문구와 로그 줄이 같은 말을 쓰게 한다.
///
/// 직접 만든 항목의 기록에는 종류가 없다(#560). 지금 카드는 기본 일곱만 그리므로 그런
/// 기록이 여기 오지 않지만, 오면 빈 칸 대신 "케어" 라고 말한다 — 조각 4 에서 카드가 항목
/// 이름을 직접 넘기면 이 함수는 마지막 대비책만 남는다.
String _labelOf(ServerCareType? type) => type?.label ?? '케어';

/// 내 기록이 있는 칸을 다시 눌렀을 때의 선택(#329).
enum _Retap { undo, again, cancel }

String retapWarning(CareLogEntry mine, String what) =>
    '오늘 ${mine.timeLabel} 에 내가 남긴 $what 기록이에요. 잘못 눌렀다면 지우고, 한 번 더 한 거면 다시 기록해요.';

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

import 'package:flutter/material.dart';

import '../data/family_repository.dart';
import '../domain/pet.dart' show careColor, careIcon, CareType;
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

  const TodayCareCard({super.key, this.onOpenFamily, this.repository});

  @override
  State<TodayCareCard> createState() => _TodayCareCardState();
}

class _TodayCareCardState extends State<TodayCareCard> {
  late final FamilyRepository _repo = widget.repository ?? FamilyRepository();

  FamilyGroupSummary? _group;
  List<CareLogEntry> _logs = const [];
  FamilyFailureKind? _failure;
  bool _loading = true;

  /// 기록을 보내는 중인 종류. 같은 칸을 두 번 눌러 두 번 보내는 것을 막는다.
  ServerCareType? _sending;

  @override
  void initState() {
    super.initState();
    kServerCareRev.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    kServerCareRev.removeListener(_reload);
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
    try {
      final group = _group ?? await _repo.myGroup();
      final logs = await _repo.careLogs(group.id);
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

  Future<void> _tap(ServerCareType type) async {
    final group = _group;
    if (group == null || _sending != null) return;

    final already = _latestOf(type);
    if (already != null) {
      final ok = await _confirmDuplicate(already);
      // await 뒤의 첫 문장에서 가른다 — 이 State 가 사라졌으면 아무것도 하지 않는다.
      if (!mounted) return;
      if (!ok) return;
    }

    setState(() => _sending = type);
    try {
      await _repo.recordCare(group.id, type);
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

  /// "오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?"
  Future<bool> _confirmDuplicate(CareLogEntry already) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFFCFAFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '오늘 이미 기록이 있어요',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          duplicateWarning(already),
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
              style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE07A4E)),
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
          const Icon(Icons.diversity_1_rounded, size: 17, color: Color(0xFFFF8F63)),
          const SizedBox(width: 6),
          const Text('오늘의 케어',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const Spacer(),
          if (widget.onOpenFamily != null)
            GestureDetector(
              onTap: widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Row(children: [
                Text('우리 가족',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
                Icon(Icons.chevron_right, size: 16, color: Color(0xFFE07A4E)),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE07A4E))),
          SizedBox(width: 8),
          Text('오늘의 케어를 불러오는 중',
              style: TextStyle(fontSize: 12.5, color: T.textMuted)),
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
              onTap: widget.onOpenFamily,
              behavior: HitTestBehavior.opaque,
              child: const Text('만들기',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            )
          else if (failure != FamilyFailureKind.noGroup)
            GestureDetector(
              onTap: _load,
              behavior: HitTestBehavior.opaque,
              child: const Text('다시 시도',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
            ),
        ]),
      );
    }

    return Row(children: [
      for (int i = 0; i < ServerCareType.values.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _cell(ServerCareType.values[i])),
      ],
    ]);
  }

  Widget _cell(ServerCareType type) {
    final done = _latestOf(type);
    final color = careColor(_iconTypeOf(type));
    final busy = _sending == type;

    return GestureDetector(
      onTap: busy ? null : () => _tap(type),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: BoxDecoration(
          color: done != null ? color.withValues(alpha: 0.13) : const Color(0xB3FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: done != null ? color.withValues(alpha: 0.35) : const Color(0x66FFFFFF)),
        ),
        child: Column(children: [
          Icon(
            done != null ? Icons.check_circle_rounded : careIcon(_iconTypeOf(type)),
            size: 19,
            color: done != null ? color : T.textMuted,
          ),
          const SizedBox(height: 4),
          Text(type.label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const SizedBox(height: 2),
          Text(
            done == null ? '아직' : '${done.doneByName} · ${done.timeLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: done != null ? color : T.textMuted),
          ),
        ]),
      ),
    );
  }

  /// 아이콘·색은 `pet.dart` 의 것을 그대로 쓴다 — 화면의 시각 언어가 갈리지 않게.
  /// 서버의 `vet`(병원)은 그쪽에 없어서 `etc` 로 떨어진다.
  static CareType _iconTypeOf(ServerCareType type) => switch (type) {
        ServerCareType.water => CareType.water,
        ServerCareType.meal => CareType.meal,
        ServerCareType.walk => CareType.walk,
        ServerCareType.med => CareType.med,
        ServerCareType.vet => CareType.etc,
      };
}

/// "오늘 14:20 아빠가 밥을 줬습니다. 그래도 기록할까요?"
///
/// 위젯 밖에 두는 이유: 이 문구가 완료 조건 2 그 자체라 **테스트가 직접 부를 수 있어야**
/// 한다. 위젯 안에 있으면 문구를 확인하는 방법이 화면을 띄우는 것뿐이다.
String duplicateWarning(CareLogEntry already) {
  final phrase = switch (already.type) {
    ServerCareType.water => '물을 갈아줬습니다',
    ServerCareType.meal => '밥을 줬습니다',
    ServerCareType.walk => '산책을 다녀왔습니다',
    ServerCareType.med => '약을 줬습니다',
    ServerCareType.vet => '병원에 다녀왔습니다',
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

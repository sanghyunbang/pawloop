import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/walk_outbox.dart';
import '../data/walk_repository.dart';
import '../data/walk_sync.dart';
import '../widgets/pet_registration_sheet.dart';

/// 산책 기록 작성 (create) — 장소·거리·시간·메모·사진.
///
/// ## 초안은 **선택**이다
///
/// 이 화면에 오는 길이 둘이다.
///
///  1. 트래킹을 끝내고 온다 — [draft] 에 실제 경로·거리·시간이 들어 있다.
///  2. `myrecords_screen` 의 "산책 기록하기" 로 바로 온다 — 초안이 없고 손으로 적는다.
///
/// 그래서 [draft] 를 필수로 만들 수 없다. 필수로 두면 두 번째 경로가 컴파일 단계에서
/// 깨진다.
///
/// ## 예전에는 거리가 하드코딩 2.0 이었다
///
/// 트래킹 화면이 실제 거리를 쌓아 놓고도 이 화면으로 넘기지 않아서, 3km 를 걸어도
/// 저장 화면은 2.0km 부터 시작했다. 그리고 저장 버튼은 스낵바만 띄웠다.
class CreateScreen extends StatefulWidget {
  final String? prefillPlace; // 장소 상세 "여기서 산책 기록 쓰기"에서 prefill

  /// 트래킹이 만든 초안. **없으면 손입력이다.**
  final WalkDraft? draft;

  const CreateScreen({super.key, this.prefillPlace, this.draft});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _place = TextEditingController();
  final _memo = TextEditingController();

  /// 초안이 있으면 그 값에서 시작한다. 없을 때만 손입력 기본값이다.
  late double km = widget.draft?.km ?? 2.0;
  late int minutes = widget.draft?.minutes ?? 30;

  /// 사용자가 거리·시간을 **직접 만졌는가.**
  ///
  /// 안 만졌으면 초안의 실측값을 그대로 보낸다. 이게 없으면 화면의 값으로 되돌려
  /// 보내게 되는데, 그 값은 분 단위라 **1분 미만이 통째로 사라진다** — 74초를 걷고
  /// 저장했더니 서버에 `duration_s = 0` 이 들어갔다(실측).
  bool _distanceEdited = false;
  bool _minutesEdited = false;

  bool _saving = false;

  static const _warm = LinearGradient(
    begin: Alignment(-0.7, -1), end: Alignment(0.7, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  void initState() {
    super.initState();
    if (widget.prefillPlace != null) _place.text = widget.prefillPlace!;
  }

  @override
  void dispose() {
    _place.dispose();
    _memo.dispose();
    super.dispose();
  }

  String get _dateLabel {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final n = DateTime.now();
    return '${n.month}월 ${n.day}일 (${w[n.weekday - 1]})';
  }

  /// 저장. **여기서 처음으로 기록이 서버로 나간다.**
  ///
  /// 화면은 결과를 있는 그대로 말한다 — 큐에 남았으면 "저장됐어요" 라고 하지 않는다.
  /// 그게 "저장은 됐는데 아무 데도 안 보인다" 를 만드는 자리다.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final memo = _memo.text.trim();
    final base = widget.draft ??
        // 손입력이다. 경로가 없고 시각은 지금 기준으로 만든다 — 지어낸 좌표를 넣지
        // 않는 것이 요점이다.
        WalkDraft.fresh(
          startedAt: DateTime.now().subtract(Duration(minutes: minutes)),
          endedAt: DateTime.now(),
          distanceM: (km * 1000).round(),
          durationS: minutes * 60,
          path: const [],
        );

    final draft = base.copyWith(
      // **만진 것만 이긴다.** 사용자가 손으로 정한 값은 실측값을 이기지만, 안 만졌으면
      // 초안의 초 단위 값을 그대로 둔다 — 화면의 분 단위로 되돌리면 1분 미만이 사라진다.
      distanceM: _distanceEdited || widget.draft == null ? (km * 1000).round() : null,
      durationS: _minutesEdited || widget.draft == null ? minutes * 60 : null,
      memo: memo.isEmpty ? null : memo,
    );

    final WalkSyncResult result;
    try {
      final sync = await WalkSync.open();
      result = await sync.push(draft);
    } catch (_) {
      // 저장소를 열지 못했다(디스크 문제 등). 기록을 잃지 않았다고 말할 수 없다.
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('기록을 저장하지 못했어요');
      return;
    }

    if (!mounted) return;

    // 반려동물이 없어서 못 올린 경우다. **스낵바로 끝내지 않는다** — 사용자는 안내를
    // 받고도 등록할 곳을 찾을 수 없었다(#159). 지금 그 자리에서 등록하게 하고, 성공하면
    // 방금 그 산책을 바로 올린다.
    if (result.outcome == WalkSyncOutcome.queued && result.needsPet) {
      final registered = await showPetRegistrationSheet(
        context,
        reason: '산책을 저장하려면 어느 아이의 산책인지 알아야 해요',
      );
      if (!mounted) return;
      if (registered != null) {
        final retried = await WalkSync.open().then((s) => s.flush());
        if (!mounted) return;
        setState(() => _saving = false);
        _toast(retried > 0
            ? '산책 기록이 저장됐어요 🐾'
            : '기록을 보관했어요 · 연결되면 올릴게요');
        Navigator.of(context).maybePop();
        return;
      }
    }

    setState(() => _saving = false);

    _toast(switch (result.outcome) {
      WalkSyncOutcome.saved => '산책 기록이 저장됐어요 🐾',
      // 사라지지 않았다는 것과, 아직 서버에 없다는 것을 둘 다 말한다.
      WalkSyncOutcome.queued =>
        result.reason ?? '기록을 보관했어요 · 연결되면 올릴게요',
      WalkSyncOutcome.rejected => result.reason ?? '기록을 저장할 수 없어요',
    });
    Navigator.of(context).maybePop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 1800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _placeCard(),
                  const SizedBox(height: 14),
                  _metricsCard(),
                  const SizedBox(height: 14),
                  _photoCard(),
                  const SizedBox(height: 14),
                  _memoCard(),
                  const SizedBox(height: 18),
                  _saveButton(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x80FFFFFF)),
              ),
              child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('산책 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: _save,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFF7E8A))),
            ),
          ),
        ]),
      );

  // 라벨 + 입력박스 헬퍼
  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: T.textSecondary));

  BoxDecoration get _fieldDeco => BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2E8C7BFF)),
      );

  // ── 장소 + 날짜 ─────────────────────────────
  Widget _placeCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('어디를 걸었나요?'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(children: [
            const Icon(Icons.place, size: 18, color: Color(0xFFFF9E7D)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _place,
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '예: 서울숲, 한강공원, 동네 한 바퀴',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _label('날짜'),
        const SizedBox(height: 7),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
          child: Row(children: [
            Text(_dateLabel, style: const TextStyle(fontSize: 14, color: Color(0xFF3A3550))),
            const Spacer(),
            const Icon(Icons.calendar_month, size: 18, color: T.textMuted),
          ]),
        ),
      ]),
    );
  }

  // ── 거리 · 시간 스텝퍼 ────────────────────────
  Widget _metricsCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('얼마나 걸었나요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        // 초안이 없으면 아래 2.0km/30분은 **측정값이 아니라 출발점**이다. 그 말을 안
        // 하면 사용자가 앱이 재어 준 값인 줄 알고 그대로 저장하고, 걷지 않은 2km 가
        // 통계에 계속 세진다. (이슈 #160)
        //
        // 지우는 것은 가능하다 — 내 기록 화면(myrecords_screen)에서 길게 눌러 지운다.
        // 하드 삭제라 되돌릴 수 없어서 그 화면이 반드시 한 번 묻는다.
        if (widget.draft == null) ...[
          const SizedBox(height: 5),
          const Row(children: [
            Icon(Icons.edit_outlined, size: 13, color: T.textMuted),
            SizedBox(width: 5),
            Expanded(
              child: Text('직접 입력하는 값이에요 · 아래 숫자는 기본값입니다',
                  style: TextStyle(fontSize: 12, color: T.textMuted)),
            ),
          ]),
        ],
        const SizedBox(height: 14),
        _stepperRow(
          icon: Icons.straighten,
          label: '거리',
          value: '${km.toStringAsFixed(1)} km',
          onMinus: () => setState(() {
            km = (km - 0.1).clamp(0.0, 99.0);
            _distanceEdited = true;
          }),
          onPlus: () => setState(() {
            km = (km + 0.1).clamp(0.0, 99.0);
            _distanceEdited = true;
          }),
        ),
        const SizedBox(height: 12),
        _stepperRow(
          icon: Icons.schedule,
          label: '시간',
          value: '$minutes 분',
          onMinus: () => setState(() {
            minutes = (minutes - 5).clamp(0, 600);
            _minutesEdited = true;
          }),
          onPlus: () => setState(() {
            minutes = (minutes + 5).clamp(0, 600);
            _minutesEdited = true;
          }),
        ),
      ]),
    );
  }

  Widget _stepperRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    Widget btn(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xC9FFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x2E8C7BFF)),
            ),
            child: Icon(i, size: 20, color: T.textSecondary),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x298C7BFF)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0x22FF9E7D), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 18, color: const Color(0xFFFF8F63)),
        ),
        const SizedBox(width: 10),
        _label(label),
        const Spacer(),
        btn(Icons.remove, onMinus),
        SizedBox(
          width: 78,
          child: Text(value, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF3A3550))),
        ),
        btn(Icons.add, onPlus),
      ]),
    );
  }

  // ── 사진(플레이스홀더) ───────────────────────
  Widget _photoCard() {
    Widget thumb(List<Color> c) => Container(
          width: 74, height: 74,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Align(
            alignment: Alignment(0, 0.4),
            child: Icon(Icons.pets, size: 22, color: Color(0x66FFFFFF)),
          ),
        );
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('사진', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 4),
        const Text('오늘 우리 아이의 산책 순간을 남겨보세요.',
            style: TextStyle(fontSize: 12, color: Color(0xA8463C64))),
        const SizedBox(height: 14),
        Row(children: [
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('사진 첨부는 곧 지원돼요'), duration: Duration(milliseconds: 1200)),
              );
            },
            child: Container(
              width: 74, height: 74, alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x59836FFF), width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.add_a_photo, size: 22, color: Color(0xFF9B8FC4)),
                SizedBox(height: 3),
                Text('추가', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9B8FC4))),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFFFD9C2), Color(0xFFFFC0B0)]),
          const SizedBox(width: 10),
          thumb(const [Color(0xFFD4ECFF), Color(0xFFD9F5EC)]),
        ]),
      ]),
    );
  }

  // ── 메모 ────────────────────────────────────
  Widget _memoCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('오늘의 산책', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 12),
        Container(
          decoration: _fieldDeco,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: TextField(
            controller: _memo,
            maxLines: 4,
            // 서버가 @Size(max=500) 이다. 여기서 막지 않으면 501자를 쓴 사람이
            // '저장' 을 누른 뒤에야 400 을 받고, 그 기록은 거절 큐로 간다 —
            // 되돌릴 수 없는 실패를 입력 단계에서 막는다. (#161)
            //
            // 숫자를 여기 적지 않는다. 저장소가 계약·컬럼 폭과 함께 들고 있는
            // 상수를 쓴다 — 두 곳에 적으면 한쪽만 바뀌는 날이 온다.
            maxLength: WalkRepository.maxMemoLength,
            style: const TextStyle(fontSize: 14, height: 1.6, color: T.textPrimary),
            decoration: const InputDecoration(
              hintText: '오늘 산책은 어땠나요? 우리 아이의 컨디션, 만난 친구, 특별했던 순간을 적어보세요...',
              hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _save,
      child: Container(
        height: 58, alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x66FF7E8A), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.pets, size: 21, color: Colors.white),
          SizedBox(width: 8),
          Text('산책 기록 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import 'family_chat_screen.dart';

/// 우리 가족 — 가족 구성원 · 오늘의 케어 공유 · 산책 주의사항 · 가족 채팅.
/// (물·밥·산책을 가족이 함께 챙기는 케어 허브)
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  @override
  void initState() {
    super.initState();
    ensureCareFreshForToday(); // 날 바뀌면 반복 항목 체크 리셋 · 일회성 제거
  }

  // 케어/주의사항 공용 삭제 확인 다이얼로그.
  Future<bool> _confirmDelete(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFFCFAFF),
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
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
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
                      color: const Color(0xB3FFFFFF),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0x80FFFFFF)),
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
                  _membersCard(),
                  const SizedBox(height: 16),
                  _careCard(),
                  const SizedBox(height: 16),
                  _distanceCard(),
                  const SizedBox(height: 16),
                  _walkNotesCard(),
                  const SizedBox(height: 16),
                  _chatBanner(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ───────────── 가족 구성원 ─────────────
  Widget _membersCard() {
    Widget member(FamilyMember m) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: m.color),
              child: Text(m.name.characters.first,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            const SizedBox(height: 7),
            Text(m.name,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            const SizedBox(height: 2),
            Text(m.role, style: const TextStyle(fontSize: 11, color: T.textMuted)),
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
            for (final m in kFamilyMembers) member(m),
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
                    color: const Color(0x66FFFFFF),
                    border: Border.all(color: const Color(0xFFFFA96B).withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: const Icon(Icons.add, size: 24, color: Color(0xFFE07A4E)),
                ),
                const SizedBox(height: 7),
                const Text('초대',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  // 초대 코드 바텀시트.
  void _openInviteSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFAFCFAFF),
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
              color: const Color(0xFFFFA96B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFA96B).withValues(alpha: 0.35)),
            ),
            child: const Text(
              kFamilyInviteCode,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: Color(0xFFE07A4E),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: kFamilyInviteCode));
              Navigator.pop(sheetCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('초대 코드가 복사되었어요'), duration: Duration(milliseconds: 1800)),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: _warm,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7E8A).withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.copy_rounded, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('코드 복사',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('가족이 이 코드로 참여해요', style: TextStyle(fontSize: 12.5, color: T.textMuted)),
        ]),
      ),
    );
  }

  // ───────────── 오늘의 케어 ─────────────
  Widget _careCard() {
    String nowHm() {
      final now = DateTime.now();
      return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }

    Widget item(CareTask t, {required bool last}) {
      final c = careColor(t.type);
      return Dismissible(
        key: ObjectKey(t),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B7E).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.delete_outline_rounded, size: 22, color: Color(0xFFFF6B7E)),
        ),
        onDismissed: (_) {
          setState(() => kCareToday.remove(t));
          kCareRev.value++;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("'${t.label}' 항목을 삭제했어요"), duration: const Duration(milliseconds: 1600)),
          );
        },
        child: GestureDetector(
        onTap: () => setState(() {
          t.done = !t.done;
          if (t.done) {
            t.by = '나';
            t.time = nowHm();
          } else {
            t.by = null;
            t.time = null;
          }
          kCareRev.value++;
        }),
        onLongPress: () async {
          if (await _confirmDelete(t.label)) {
            setState(() => kCareToday.remove(t));
            kCareRev.value++;
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: Color(0x1A8C7BFF))),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(careIcon(t.type), size: 20, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.done ? T.textMuted : T.textPrimary,
                      decoration: t.done ? TextDecoration.lineThrough : null,
                    )),
                if (t.product != null) ...[
                  const SizedBox(height: 3),
                  Text(t.product!, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                ],
              ]),
            ),
            Text(
              t.done ? '${t.by} · ${t.time}' : '아직',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: t.done ? const Color(0xFF3EA772) : T.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              t.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 21,
              color: t.done ? const Color(0xFF57C98A) : T.textFaint,
            ),
          ]),
        ),
      ),
      );
    }

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('오늘의 케어',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          Text('탭 완료 · 길게 눌러 삭제', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
        const SizedBox(height: 4),
        if (kCareToday.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('아직 케어 항목이 없어요 · 아래에서 추가해 보세요',
                style: TextStyle(fontSize: 13, color: T.textMuted)),
          )
        else
          for (int i = 0; i < kCareToday.length; i++)
            item(kCareToday[i], last: i == kCareToday.length - 1),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _openAddCareSheet,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA96B).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFFFA96B).withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.add_rounded, size: 19, color: Color(0xFFE07A4E)),
              SizedBox(width: 6),
              Text('케어 항목 추가',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
            ]),
          ),
        ),
      ]),
    );
  }

  // 케어 항목 추가 시트 — 가족 누구나 자유롭게 등록.
  void _openAddCareSheet() {
    CareType selType = CareType.etc;
    bool daily = true;
    final labelCtrl = TextEditingController();
    final productCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFAFCFAFF),
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
            const Text('케어 항목 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
            const SizedBox(height: 4),
            const Text('가족 모두의 오늘의 케어에 추가돼요', style: TextStyle(fontSize: 12.5, color: T.textMuted)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in CareType.values)
                GestureDetector(
                  onTap: () => setSheet(() => selType = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: selType == t ? careColor(t) : const Color(0xFFF1ECF7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(careIcon(t), size: 15, color: selType == t ? Colors.white : T.textSecondary),
                      const SizedBox(width: 5),
                      Text(t.label,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                              color: selType == t ? Colors.white : T.textSecondary)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x9EFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x338C7BFF)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: labelCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '항목 이름 (예: 저녁 약, 빗질, 놀아주기)',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            // 밥/간식은 제품명(선택) 입력 — 추후 소진 예측·추천의 재료. 강제 아님.
            if (selType == CareType.meal || selType == CareType.snack) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0x9EFFFFFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x338C7BFF)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: productCtrl,
                  style: const TextStyle(fontSize: 15, color: T.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '제품명 (선택 · 예: 로얄캐닌 미니 어덜트)',
                    hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // 매일 반복 여부 — 반복이면 날마다 체크만 초기화, 끄면 오늘 하루만.
            GestureDetector(
              onTap: () => setSheet(() => daily = !daily),
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                Icon(Icons.repeat_rounded, size: 18, color: daily ? const Color(0xFFE07A4E) : T.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('매일 반복', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
                    const SizedBox(height: 2),
                    Text(daily ? '매일 아침 체크만 초기화되고 항목은 유지돼요' : '오늘 하루만 — 내일이면 자동으로 사라져요',
                        style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
                  ]),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46, height: 27,
                  padding: const EdgeInsets.all(3),
                  alignment: daily ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    gradient: daily ? _warm : null,
                    color: daily ? null : const Color(0x1F8C7BFF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Container(
                    width: 21, height: 21,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                final product = productCtrl.text.trim();
                setState(() => kCareToday.add(CareTask(
                    type: selType, label: label, product: product.isEmpty ? null : product, daily: daily)));
                kCareRev.value++;
                Navigator.pop(sheetCtx);
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
        );
      }),
    );
  }

  // ───────────── 오늘 걸은 거리 (가족 공유 — 위치정보 제3자 제공) ─────────────
  Widget _distanceCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: kShareMyDistance,
      builder: (context, sharing, __) {
        final maxKm = kFamilyMembers.fold<double>(0.1, (m, f) => f.todayKm > m ? f.todayKm : m);

        Widget memberRow(FamilyMember m) {
          final isMe = m.name == '나';
          final hidden = isMe && !sharing;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: m.color),
                child: Text(m.name.characters.first,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 42,
                child: Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textPrimary)),
              ),
              Expanded(
                child: hidden
                    ? const Text('공유 꺼짐 — 오른쪽 스위치로 켤 수 있어요',
                        style: TextStyle(fontSize: 12, color: T.textMuted))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (m.todayKm / maxKm).clamp(0.02, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [m.color.withValues(alpha: 0.75), m.color]),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ]),
              ),
              const SizedBox(width: 10),
              Text(hidden ? '-' : '${m.todayKm.toStringAsFixed(1)}km',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: hidden ? T.textMuted : T.textSecondary)),
            ]),
          );
        }

        return GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.route_rounded, size: 18, color: Color(0xFF33BFA6)),
              const SizedBox(width: 7),
              const Text('오늘 걸은 거리',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
              const Spacer(),
              // 내 거리 공유 토글(제3자 제공 동의 — 켤 때 동의 시트 필수)
              GestureDetector(
                onTap: () => _toggleShare(sharing),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46, height: 27,
                  padding: const EdgeInsets.all(3),
                  alignment: sharing ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    gradient: sharing ? _warm : null,
                    color: sharing ? null : const Color(0x1F8C7BFF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Container(
                    width: 21, height: 21,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(sharing ? '내 거리가 가족에게 공유되고 있어요' : '내 거리 공유가 꺼져 있어요',
                style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
            const SizedBox(height: 14),
            for (final m in kFamilyMembers) memberRow(m),
            const Text('내 거리·위치는 동의한 가족에게만 제공되고, 제공될 때마다 알림으로 알려드려요',
                style: TextStyle(fontSize: 11, color: T.textMuted)),
          ]),
        );
      },
    );
  }

  void _toggleShare(bool current) {
    if (current) {
      kShareMyDistance.value = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가족 거리 공유를 중단했어요'), duration: Duration(milliseconds: 1600)),
      );
    } else {
      _openShareConsentSheet();
    }
  }

  // 제3자 제공 동의 시트 — 위치정보법 요건(제공받는 자·목적·기간 고지 후 명시적 동의).
  void _openShareConsentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFAFCFAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 42, height: 5,
              decoration: BoxDecoration(color: const Color(0x2E281E30), borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 18),
          const Text('가족에게 내 산책 거리를 공유할까요?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 14),
          _consentRow('제공받는 자', '내가 속한 가족 그룹의 구성원'),
          _consentRow('제공 목적', '가족 간 산책 거리·활동 공유'),
          _consentRow('보유·이용 기간', '공유를 끄거나 그룹을 나갈 때까지'),
          _consentRow('통지', '내 위치·거리가 제공될 때마다 알림으로 알려드려요'),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              kShareMyDistance.value = true;
              Navigator.pop(sheetCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('공유를 시작했어요 · 제공될 때마다 알림으로 알려드려요'),
                  duration: Duration(milliseconds: 2000),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(15)),
              child: const Text('동의하고 공유 시작',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(sheetCtx),
              child: const Text('다음에 할게요', style: TextStyle(fontSize: 13.5, color: T.textMuted)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _consentRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 92,
            child: Text(k, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: T.textSecondary)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xCC463C64)))),
        ]),
      );

  // ───────────── 산책 주의사항 (가족 누구나 추가/삭제) ─────────────
  Widget _walkNotesCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.report_gmailerrorred_rounded, size: 18, color: Color(0xFFE07A4E)),
          SizedBox(width: 7),
          Text('산책 주의사항',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          Text('길게 눌러 삭제', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
        const SizedBox(height: 12),
        if (kWalkNotes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 9),
            child: Text('아직 주의사항이 없어요 · 가족과 공유할 메모를 남겨보세요',
                style: TextStyle(fontSize: 13, color: T.textMuted)),
          )
        else
          for (int i = 0; i < kWalkNotes.length; i++)
            Dismissible(
              key: ValueKey('walk-note-$i-${kWalkNotes[i]}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B7E).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFFF6B7E)),
              ),
              onDismissed: (_) => setState(() => kWalkNotes.removeAt(i)),
              child: GestureDetector(
                onLongPress: () async {
                  if (await _confirmDelete(kWalkNotes[i])) {
                    setState(() => kWalkNotes.removeAt(i));
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFA96B)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(kWalkNotes[i],
                        style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary)),
                  ),
                ]),
              ),
              ),
            ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _openAddNoteSheet,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA96B).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFA96B).withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.add_rounded, size: 18, color: Color(0xFFE07A4E)),
              SizedBox(width: 5),
              Text('주의사항 추가',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text('주의사항은 가족 모두에게 보여요', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
      ]),
    );
  }

  // 주의사항 추가 시트.
  void _openAddNoteSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFAFCFAFF),
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
              color: const Color(0x9EFFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x338C7BFF)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              minLines: 1,
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
              setState(() => kWalkNotes.add(text));
              Navigator.pop(sheetCtx);
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

  // ───────────── 가족 채팅 배너 ─────────────
  Widget _chatBanner() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FamilyChatScreen()),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: _warm,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7E8A).withValues(alpha: 0.28),
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
              color: Colors.white.withValues(alpha: 0.22),
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
              Text(
                kChatMessages.last.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xE6FFFFFF)),
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

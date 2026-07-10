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
      return GestureDetector(
        onTap: () => setState(() {
          t.done = !t.done;
          if (t.done) {
            t.by = '나';
            t.time = nowHm();
          } else {
            t.by = null;
            t.time = null;
          }
        }),
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
              child: Text(t.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: t.done ? T.textMuted : T.textPrimary,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                  )),
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
      );
    }

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('오늘의 케어',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          Text('탭해서 완료 표시', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
        const SizedBox(height: 4),
        for (int i = 0; i < kCareToday.length; i++)
          item(kCareToday[i], last: i == kCareToday.length - 1),
      ]),
    );
  }

  // ───────────── 산책 주의사항 ─────────────
  Widget _walkNotesCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.report_gmailerrorred_rounded, size: 18, color: Color(0xFFE07A4E)),
          SizedBox(width: 7),
          Text('산책 주의사항',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 12),
        for (final note in kWalkNotes)
          Padding(
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
                child: Text(note,
                    style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary)),
              ),
            ]),
          ),
        const SizedBox(height: 2),
        const Text('주의사항은 가족 모두에게 보여요', style: TextStyle(fontSize: 11.5, color: T.textMuted)),
      ]),
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

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../widgets/aurora.dart';
import 'detail_screen.dart';

/// 오늘 화면 — design_refactor 핸드오프 'today' 스크린 재현.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int emo = 4; // 평온
  int intensity = 2; // 보통
  final List<int> todayLog = [2, 1];

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String get _dateLabel {
    final n = DateTime.now();
    final w = _weekdays[(n.weekday - 1) % 7];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}. ${two(n.month)}. ${two(n.day)} $w요일';
  }

  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(initialEmo: emo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = kEmotions[emo];
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        tint: e,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  children: [
                    Text(_dateLabel,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Color(0xBD463C69))),
                    const SizedBox(height: 8),
                    const Text('오늘, 어떤 마음에\n가까운가요?',
                        style: TextStyle(
                            fontSize: 27,
                            height: 1.25,
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w800,
                            color: T.textPrimary)),
                    const SizedBox(height: 10),
                    Center(child: FloatingOrb(emotion: e, size: 188)),
                    const SizedBox(height: 8),
                    Center(
                      child: Column(children: [
                        Text(e.label,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: T.textPrimary)),
                        const SizedBox(height: 5),
                        Text(e.desc,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xBD463C64))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _chips(),
                    const SizedBox(height: 18),
                    GlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(children: [
                        _intensity(e),
                        const SizedBox(height: 16),
                        _todayRecord(),
                        const SizedBox(height: 14),
                        _ctas(e),
                        const SizedBox(height: 8),
                        _detailLink(),
                      ]),
                    ),
                  ],
                ),
              ),
              _bottomNav(e),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      alignment: WrapAlignment.center,
      children: [for (int i = 0; i < kEmotions.length; i++) _chip(i)],
    );
  }

  Widget _chip(int i) {
    final em = kEmotions[i];
    final on = i == emo;
    return GestureDetector(
      onTap: () => setState(() => emo = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          gradient: on ? em.grad : null,
          color: on ? null : const Color(0xC2FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Colors.transparent : const Color(0x66FFFFFF)),
          boxShadow: on
              ? [BoxShadow(color: em.c2.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(em.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(em.label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _intensity(Emotion e) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('감정의 세기',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(gradient: e.grad, borderRadius: BorderRadius.circular(10)),
          child: Text(kLevels[intensity],
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => intensity = i),
                  child: Container(
                    height: 18.0 + i * 6.5,
                    decoration: BoxDecoration(
                      gradient: i <= intensity ? e.grad : null,
                      color: i <= intensity ? null : const Color(0x1F785AA0),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  Widget _todayRecord() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x59FFFFFF),
        border: Border.all(color: const Color(0x80FFFFFF)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(children: [
        const Text('오늘 기록',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            for (final i in todayLog) ...[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: kEmotions[i].grad),
                child: Text(kEmotions[i].emoji, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 5),
            ],
          ]),
        ),
        Text('${todayLog.length}번 기록',
            style: const TextStyle(fontSize: 11.5, color: Color(0x8C463C64))),
      ]),
    );
  }

  Widget _ctas(Emotion e) {
    return Row(children: [
      Expanded(child: _btn(icon: Icons.edit_note, label: '기록하기', gradient: e.grad, onTap: () {})),
      const SizedBox(width: 11),
      Expanded(child: _btn(icon: Icons.favorite_border, label: '위로받기', gradient: null, onTap: _openDetail)),
    ]);
  }

  Widget _btn({required IconData icon, required String label, required Gradient? gradient, required VoidCallback onTap}) {
    final filled = gradient != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradient,
          color: filled ? null : const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: filled ? Colors.transparent : const Color(0x80FFFFFF)),
          boxShadow: filled
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 8))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: filled ? Colors.white : T.textSecondary),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _detailLink() {
    return GestureDetector(
      onTap: _openDetail,
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('더 정확히 입력하기',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xB3463C64))),
          SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 17, color: Color(0xB3463C64)),
        ]),
      ),
    );
  }

  Widget _bottomNav(Emotion e) {
    Widget item(IconData icon, String label, bool active) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 23, color: active ? e.c2 : T.textMuted),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? e.c2 : T.textMuted)),
          ]),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 8 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xE6FFFFFF),
        border: Border(top: BorderSide(color: Color(0x22785AA0))),
      ),
      child: Row(children: [
        item(Icons.wb_sunny_outlined, '오늘', true),
        item(Icons.explore_outlined, '탐색', false),
        Expanded(
          child: Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF9FCF), Color(0xFFFF8FA8)],
                ),
                boxShadow: [BoxShadow(color: Color(0x4DFF8FA8), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 24),
            ),
          ),
        ),
        item(Icons.chat_bubble_outline, '커뮤니티', false),
        item(Icons.show_chart, '흐름', false),
      ]),
    );
  }
}

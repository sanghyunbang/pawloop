import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'detail_screen.dart';
import 'analyzing_screen.dart';

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

  void _openAnalyzing() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnalyzingScreen(emo: emo)),
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
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, MediaQuery.of(context).padding.bottom + 126),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_dateLabel,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Color(0xBD463C69))),
                      const SizedBox(height: 6),
                      const Text('오늘, 어떤 마음에\n가까운가요?',
                          style: TextStyle(fontSize: 25, height: 1.25, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  const ProfileAvatar(),
                ]),
                // 오브 + 라벨 (남는 공간을 채워 화면 한 장에 맞춤)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingOrb(emotion: e, size: 152),
                        const SizedBox(height: 14),
                        Text(e.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
                        const SizedBox(height: 4),
                        Text(e.desc, style: const TextStyle(fontSize: 13.5, color: Color(0xBD463C64))),
                      ],
                    ),
                  ),
                ),
                _chips(),
                const SizedBox(height: 16),
                _intensity(e),
                const SizedBox(height: 13),
                _todayRecord(),
                const SizedBox(height: 12),
                _ctas(e),
                const SizedBox(height: 12),
                _detailLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    Widget row(int a, int b, int c) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _chip(a),
          const SizedBox(width: 10),
          _chip(b),
          const SizedBox(width: 10),
          _chip(c),
        ]);
    return Column(children: [row(0, 1, 2), const SizedBox(height: 10), row(3, 4, 5)]);
  }

  Widget _chip(int i) {
    final em = kEmotions[i];
    final on = i == emo;
    return GestureDetector(
      onTap: () => setState(() => emo = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 10),
        decoration: BoxDecoration(
          gradient: on ? em.grad : null,
          color: on ? null : const Color(0xC9FFFFFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: on ? Colors.transparent : const Color(0x73FFFFFF)),
          boxShadow: on
              ? [BoxShadow(color: em.c2.withOpacity(0.32), blurRadius: 12, offset: const Offset(0, 5))]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(em.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(em.label,
              style: TextStyle(
                  fontSize: 12.5,
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
      Expanded(child: _btn(icon: Icons.favorite_border, label: '위로받기', gradient: null, onTap: _openAnalyzing)),
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
}

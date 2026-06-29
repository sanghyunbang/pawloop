import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/situations.dart';
import '../widgets/aurora.dart';
import 'analyzing_screen.dart';

/// 마음 입력 (detail) — design_refactor 'detail' 스크린 재현.
class DetailScreen extends StatefulWidget {
  final int initialEmo;
  const DetailScreen({super.key, this.initialEmo = 4});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late int emo = widget.initialEmo;
  int situ = 0; // 취업·진로
  double energy = 75;
  double social = 65;

  @override
  Widget build(BuildContext context) {
    final e = kEmotions[emo];
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
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
                  const Text('마음 입력',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ]),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  children: [
                    _aiBanner(),
                    const SizedBox(height: 14),
                    _card('지금 마음', _emoGrid(e)),
                    const SizedBox(height: 14),
                    _card('무엇이 마음을 움직였나요?', _situGrid(),
                        sub: '상황을 알려주면 AI가 훨씬 정확하게 도와줘요.'),
                    const SizedBox(height: 14),
                    _card('지금 컨디션', _condition(e)),
                    const SizedBox(height: 14),
                    _card('자유롭게', _freeText(), trailingSparkle: true),
                    const SizedBox(height: 18),
                    _analyzeBtn(e),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x29FF9E7D), Color(0x24D89BFF)],
        ),
        border: Border.all(color: const Color(0x4DD89BFF)),
        borderRadius: BorderRadius.circular(T.radius),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: T.sig, borderRadius: BorderRadius.circular(14), boxShadow: const [
            BoxShadow(color: Color(0x66D89BFF), blurRadius: 18, offset: Offset(0, 8)),
          ]),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('마음을 자세히 들려주세요',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
            SizedBox(height: 3),
            Text('AI가 맥락을 읽고, 꼭 맞는 위로와 장소를 찾아드려요.',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xB8463C64))),
          ]),
        ),
      ]),
    );
  }

  Widget _card(String title, Widget body, {String? sub, bool trailingSparkle = false}) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
          if (trailingSparkle) ...[
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFD89BFF)),
          ],
        ]),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xA8463C64))),
        ],
        const SizedBox(height: 13),
        body,
      ]),
    );
  }

  Widget _emoGrid(Emotion sel) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: [
        for (int i = 0; i < kEmotions.length; i++)
          GestureDetector(
            onTap: () => setState(() => emo = i),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: i == emo ? kEmotions[i].grad : null,
                color: i == emo ? null : const Color(0x80FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: i == emo ? Colors.transparent : const Color(0x66FFFFFF)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(kEmotions[i].emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 5),
                Text(kEmotions[i].label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i == emo ? Colors.white : T.textSecondary)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _situGrid() {
    const coral = Color(0xFFFF7A59);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 9,
      mainAxisSpacing: 9,
      childAspectRatio: 3.1,
      children: [
        for (int i = 0; i < kSituations.length; i++)
          GestureDetector(
            onTap: () => setState(() => situ = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: i == situ ? const Color(0x14FF7A59) : const Color(0x80FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: i == situ ? coral : const Color(0x66FFFFFF), width: i == situ ? 1.4 : 1),
              ),
              child: Row(children: [
                Icon(kSituations[i].icon, size: 18, color: i == situ ? coral : T.textSecondary),
                const SizedBox(width: 8),
                Text(kSituations[i].label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: i == situ ? coral : T.textSecondary)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _condition(Emotion e) {
    return Column(children: [
      _slider('에너지', '피곤함 — 활기참', energy, (v) => setState(() => energy = v)),
      const SizedBox(height: 18),
      _slider('사교성', '혼자 — 함께', social, (v) => setState(() => social = v)),
    ]);
  }

  Widget _slider(String label, String hint, double value, ValueChanged<double> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
        Text(hint, style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
      ]),
      const SizedBox(height: 11),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final knobX = (value / 100) * (w - 22);
        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            final nx = (d.localPosition.dx / w * 100).clamp(0.0, 100.0);
            onChanged(nx);
          },
          onTapDown: (d) => onChanged((d.localPosition.dx / w * 100).clamp(0.0, 100.0)),
          child: SizedBox(
            height: 22,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                    color: const Color(0x22785AA0), borderRadius: BorderRadius.circular(999)),
              ),
              FractionallySizedBox(
                widthFactor: (value / 100).clamp(0.02, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: knobX,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFF8A5C), width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _freeText() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        border: Border.all(color: const Color(0x2E8C7BFF)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text('무슨 일이 있었는지 편하게 적어주세요. AI가 맥락을 함께 읽어요.',
          style: TextStyle(fontSize: 14, height: 1.6, color: T.textMuted)),
    );
  }

  Widget _analyzeBtn(Emotion e) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AnalyzingScreen(emo: emo, situ: situ)),
      ),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: e.grad,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: e.c2.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('분석 시작하기', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../widgets/aurora.dart';
import 'result_screen.dart';

/// 분석 연출 (analyzing) — 3단계 진행 후 result로 전환.
class AnalyzingScreen extends StatefulWidget {
  final int emo;
  final int? situ;
  const AnalyzingScreen({super.key, required this.emo, this.situ});
  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen> with SingleTickerProviderStateMixin {
  int step = 0;
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  static const _steps = [
    '지금의 마음을 읽고 있어요',
    '비슷한 상황의 1,240명을 살펴보는 중',
    '꼭 맞는 위로와 장소를 고르는 중',
  ];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) setState(() => step = 1);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) setState(() => step = 2);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultScreen(emo: widget.emo, situ: widget.situ)),
      );
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = kEmotions[widget.emo];
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        tint: e,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingOrb(emotion: e, size: 188),
                const SizedBox(height: 26),
                const Text('마음을 분석하고 있어요',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 10),
                const Text('AI가 당신의 기록과 비슷한 상황을\n함께 살펴보고 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xB8463C64))),
                const SizedBox(height: 34),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    children: [
                      for (int i = 0; i < _steps.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _stepRow(i),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(int i) {
    final done = i < step;
    final active = i == step;
    Widget icon;
    if (done) {
      icon = const Icon(Icons.check_circle, size: 22, color: Color(0xFF33BFA6));
    } else if (active) {
      icon = RotationTransition(
        turns: _spin,
        child: const Icon(Icons.sync, size: 22, color: Color(0xFFFF7A59)),
      );
    } else {
      icon = const Icon(Icons.circle_outlined, size: 22, color: Color(0xFFCFC7DD));
    }
    final dim = !done && !active;
    return Row(children: [
      icon,
      const SizedBox(width: 12),
      Expanded(
        child: Text(_steps[i],
            style: TextStyle(
                fontSize: 14,
                fontWeight: dim ? FontWeight.w500 : FontWeight.w700,
                color: dim ? T.textMuted : T.textPrimary)),
      ),
    ]);
  }
}

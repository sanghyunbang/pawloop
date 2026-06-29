import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/situations.dart';
import '../theme/places.dart';
import '../widgets/aurora.dart';
import 'main_shell.dart';
import 'place_detail_screen.dart';

/// 마음 분석 결과 (result) — 조언 + 집단 인사이트 + 장소 추천(A→B) + 피드백.
class ResultScreen extends StatefulWidget {
  final int emo;
  final int? situ;
  const ResultScreen({super.key, required this.emo, this.situ});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  int? feedback; // 1=도움돼요, 0=글쎄요

  @override
  Widget build(BuildContext context) {
    final e = kEmotions[widget.emo];
    final s = widget.situ != null ? kSituations[widget.situ!] : null;
    final advice = s?.advice ?? kGenericComfort[widget.emo];
    final insight = s?.insight ?? '비슷한 마음의 사람들이 아래 장소에서 위로를 얻었어요.';
    final tip = s?.tip;

    final target = kSoothe[widget.emo];
    final recs = kPlaces.where((p) => p.to == target).toList()
      ..sort((a, b) => b.lift.compareTo(a.lift));

    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        tint: e,
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
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
                const Text('마음 분석 결과',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                children: [
                  Row(children: const [
                    Icon(Icons.auto_awesome, size: 15, color: Color(0xFFD89BFF)),
                    SizedBox(width: 5),
                    Text('AI가 당신의 상황을 분석했어요',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xA8463C64))),
                  ]),
                  const SizedBox(height: 12),
                  _adviceCard(e, s, advice),
                  const SizedBox(height: 13),
                  _insightCard(insight, tip),
                  const SizedBox(height: 18),
                  const Text('지금 가면 좋은 곳',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  const SizedBox(height: 11),
                  for (final p in recs) ...[_recCard(p, tip), const SizedBox(height: 11)],
                  const SizedBox(height: 4),
                  _feedbackCard(),
                  const SizedBox(height: 12),
                  _moreButtons(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _adviceCard(Emotion e, Situation? s, String advice) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(gradient: e.grad, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x14FF7A59),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s?.icon ?? Icons.favorite, size: 14, color: const Color(0xFFFF7A59)),
              const SizedBox(width: 5),
              Text(s?.label ?? e.label,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFFF7A59))),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(advice,
            style: const TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w600, color: T.textPrimary)),
      ]),
    );
  }

  Widget _insightCard(String insight, String? tip) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.groups, size: 18, color: Color(0xFF8E7BFF)),
          SizedBox(width: 7),
          Text('비슷한 상황의 사람들',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
        const SizedBox(height: 10),
        Text(insight, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xCC463C64))),
        if (tip != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x1A33BFA6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.directions_walk, size: 15, color: Color(0xFF2E9E88)),
              const SizedBox(width: 6),
              Text(tip, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF2E9E88))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _recCard(Place p, String? tip) {
    final to = kEmotions[p.to];
    final from = kEmotions[p.from];
    final recLine = tip != null ? '비슷한 상황에 추천돼요 · $tip' : '비슷한 마음에 추천돼요';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceDetailScreen(place: p))),
      child: GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: to.grad, borderRadius: BorderRadius.circular(16)),
            child: Text(to.emoji, style: const TextStyle(fontSize: 25)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(p.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: to.c2.withOpacity(0.14), borderRadius: BorderRadius.circular(9)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.trending_up, size: 12, color: to.c2),
                    const SizedBox(width: 2),
                    Text('+${p.lift}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: to.c2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 3),
              Text('${p.cat} · ${p.dist}', style: const TextStyle(fontSize: 12, color: T.textMuted)),
              const SizedBox(height: 5),
              Text(recLine, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xCC463C64))),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Container(height: 1, color: const Color(0x14785AA0)),
        const SizedBox(height: 9),
        Row(children: [
          _miniDot(from),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 14, color: T.textMuted),
          const SizedBox(width: 6),
          _miniDot(to),
          const SizedBox(width: 7),
          Text('${from.label} → ${to.label}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          const Spacer(),
          Text('${p.n}명 호전', style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
        ]),
      ]),
    ));
  }

  Widget _miniDot(Emotion e) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
        child: Text(e.emoji, style: const TextStyle(fontSize: 11)),
      );

  Widget _feedbackCard() {
    Widget btn(int v, IconData icon, String label) {
      final on = feedback == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => feedback = v),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? const Color(0x1A8E7BFF) : const Color(0x99FFFFFF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: on ? const Color(0xFF8E7BFF) : const Color(0x66FFFFFF), width: on ? 1.4 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: on ? const Color(0xFF8E7BFF) : T.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? const Color(0xFF8E7BFF) : T.textSecondary)),
            ]),
          ),
        ),
      );
    }

    return GlassCard(
      child: Column(children: [
        const Text('이 추천이 마음에 들었나요?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary)),
        const SizedBox(height: 12),
        Row(children: [
          btn(1, Icons.thumb_up_alt_outlined, '도움돼요'),
          const SizedBox(width: 10),
          btn(0, Icons.thumb_down_alt_outlined, '글쎄요'),
        ]),
        const SizedBox(height: 10),
        const Text('선택할수록 추천이 당신에게 더 똑똑해져요',
            style: TextStyle(fontSize: 11.5, color: T.textMuted)),
      ]),
    );
  }

  Widget _moreButtons() {
    Widget bar(IconData icon, String label, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x99FFFFFF),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 19, color: T.textSecondary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ]),
          ),
        );
    void go(String view) => RootTab.go(context, 1, exView: view);
    return Column(children: [
      bar(Icons.map_outlined, '지도에서 더 둘러보기', () => go('map')),
      const SizedBox(height: 10),
      bar(Icons.format_list_bulleted, '추천 장소 더보기', () => go('list')),
    ]);
  }
}

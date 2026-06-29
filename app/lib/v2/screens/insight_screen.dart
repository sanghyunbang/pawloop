import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/insight_data.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';

/// 마음 흐름 (insight) — 오늘/주간 차트 + 통계 + 나를 바꿔준 곳.
class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  String chartView = 'day'; // 'day' | 'week'
  String? tip; // 'total' | 'better' | 'places'

  static const _sig = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)],
  );
  static const _pink = LinearGradient(colors: [Color(0xFFFF8FB0), Color(0xFFFF9FCF)]);

  Widget _gradNum(String v, {double size = 21}) => ShaderMask(
        shaderCallback: (r) => _sig.createShader(r),
        child: Text(v, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
                children: [
                  _header(),
                  const SizedBox(height: 18),
                  _statsCard(),
                  if (tip != null) ...[const SizedBox(height: 10), _tipBox()],
                  const SizedBox(height: 14),
                  _toggle(),
                  const SizedBox(height: 14),
                  if (chartView == 'day') ...[
                    _todayCutCard(),
                    const SizedBox(height: 14),
                    _dayFlowCard(),
                  ] else ...[
                    _candleCard(),
                    const SizedBox(height: 14),
                    _weekStatsGrid(),
                    const SizedBox(height: 14),
                    _aiCard(),
                  ],
                  const SizedBox(height: 14),
                  _myShiftsCard(),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('마음 흐름', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.textPrimary)),
          SizedBox(height: 4),
          Text('내가 나를 알아가는 곳', style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
        ]),
        const Spacer(),
        const ProfileAvatar(size: 44),
      ]);

  Widget _statsCard() {
    Widget cell(InsightStat s) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => tip = tip == s.tipKey ? null : s.tipKey),
            behavior: HitTestBehavior.opaque,
            child: Column(children: [
              _gradNum(s.value),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(s.label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
                const SizedBox(width: 3),
                const Icon(Icons.info_outline, size: 13, color: Color(0xFFBBB3CC)),
              ]),
            ]),
          ),
        );
    Widget div() => Container(width: 1, height: 38, color: const Color(0x248C7BFF));
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(children: [cell(kInsightStats[0]), div(), cell(kInsightStats[1]), div(), cell(kInsightStats[2])]),
    );
  }

  Widget _tipBox() {
    final (title, text) = kStatTips[tip]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0x1A8E7BFF), Color(0x14D89BFF)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x388E7BFF)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info, size: 18, color: Color(0xFF8E7BFF)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            const SizedBox(height: 3),
            Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xCC3C345A))),
          ]),
        ),
      ]),
    );
  }

  Widget _toggle() {
    Widget seg(String v, String label) {
      final on = chartView == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => chartView = v),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: on ? _pink : null, borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: on ? Colors.white : T.textSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(children: [seg('week', '주간'), seg('day', '오늘')]),
    );
  }

  // ── 오늘 ─────────────────────────────────────────
  ({List<int> ohlc, int change}) _ohlc() {
    final ds = kDayFlow.map((e) => kScore[e.$2]).toList();
    final open = ds.first, close = ds.last;
    final hi = ds.reduce((a, b) => a > b ? a : b);
    final lo = ds.reduce((a, b) => a < b ? a : b);
    return (ohlc: [open, hi, lo, close], change: close - open);
  }

  Widget _todayCutCard() {
    final r = _ohlc();
    const keys = ['시', '고', '저', '종'];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('오늘의 한 컷', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(color: const Color(0x2433BFA6), borderRadius: BorderRadius.circular(11)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.trending_up, size: 15, color: Color(0xFF22A892)),
              const SizedBox(width: 4),
              Text('${r.change >= 0 ? '+' : ''}${r.change} ${r.change >= 0 ? '호전' : '하락'}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF22A892))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          for (int i = 0; i < 4; i++)
            Expanded(child: _ohlcCol(keys[i], kScore.indexOf(r.ohlc[i]))),
        ]),
      ]),
    );
  }

  Widget _ohlcCol(String k, int emoIdx) {
    final e = kEmotions[emoIdx];
    return Column(children: [
      Text(k, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: T.textMuted)),
      const SizedBox(height: 7),
      Container(
        width: 30, height: 30, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
        child: e.icon(19.6),
      ),
      const SizedBox(height: 6),
      Text(e.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: T.textSecondary)),
    ]);
  }

  Widget _dayFlowCard() {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('하루의 흐름', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
        const SizedBox(height: 16),
        for (int i = 0; i < kDayFlow.length; i++) ...[
          if (i > 0) const SizedBox(height: 15),
          _dayFlowRow(kDayFlow[i].$1, kDayFlow[i].$2),
        ],
      ]),
    );
  }

  Widget _dayFlowRow(String time, int emoIdx) {
    final e = kEmotions[emoIdx];
    final sc = kScore[emoIdx];
    return Row(children: [
      SizedBox(width: 32, child: Text(time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: T.textMuted))),
      const SizedBox(width: 12),
      Container(
        width: 36, height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
        child: e.icon(22.4),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3A3550))),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: sc / 100,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(gradient: e.grad, borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── 주간 ─────────────────────────────────────────
  Widget _candleCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('이번 주 마음 캔들', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const Spacer(),
          _legend(const Color(0xFF33BFA6), '좋아짐'),
          const SizedBox(width: 11),
          _legend(const Color(0xFFFF6B7E), '내려감'),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 188, child: CustomPaint(size: Size.infinite, painter: _CandlePainter())),
        const SizedBox(height: 4),
        Row(children: [
          for (int i = 0; i < kWeekCandles.length; i++)
            Expanded(
              child: Center(
                child: Text(kWeekCandles[i].lab,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: i == kTodayCandle ? FontWeight.w800 : FontWeight.w600,
                        color: i == kTodayCandle ? const Color(0xFFFF7A59) : T.textMuted)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: T.textSecondary)),
      ]);

  Widget _weekStatsGrid() {
    Widget cell((String, String) w) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.$1, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
              const SizedBox(height: 5),
              _gradNum(w.$2),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [cell(kWeekStats[0]), const SizedBox(width: 10), cell(kWeekStats[1])]),
      const SizedBox(height: 10),
      Row(children: [cell(kWeekStats[2]), const SizedBox(width: 10), cell(kWeekStats[3])]),
    ]);
  }

  Widget _aiCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0x1F8E7BFF), Color(0x1AD89BFF)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x3D8E7BFF)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.insights, size: 21, color: Color(0xFF8E7BFF)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI 패턴 분석', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8E7BFF))),
            const SizedBox(height: 3),
            Text(kChartInsight, style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xD63C345A))),
          ]),
        ),
      ]),
    );
  }

  // ── 공통 ─────────────────────────────────────────
  Widget _myShiftsCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('나를 바꿔준 곳', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
          Spacer(),
          Text('자주 마음이 나아진 장소', style: TextStyle(fontSize: 12, color: Color(0x99463C64))),
        ]),
        for (int i = 0; i < kMyShifts.length; i++) _shiftRow(kMyShifts[i], i < kMyShifts.length - 1),
      ]),
    );
  }

  Widget _shiftRow(MyShift m, bool border) {
    final f = kEmotions[m.from], t = kEmotions[m.to];
    Widget dot(Emotion e, double s) => Container(
          width: s, height: s, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: e.grad),
          child: e.icon((s * 0.5) * 1.4));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: border ? const Border(bottom: BorderSide(color: Color(0x1A8C7BFF))) : null,
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: t.grad, borderRadius: BorderRadius.circular(13)),
          child: t.icon(25.2),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            const SizedBox(height: 5),
            Row(children: [
              dot(f, 22),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 14, color: Color(0xFFBBB3CC)),
              const SizedBox(width: 6),
              dot(t, 22),
              const SizedBox(width: 8),
              Text('${f.label} → ${t.label}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: T.textSecondary)),
            ]),
          ]),
        ),
        Text(m.count, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0x80463C64))),
      ]),
    );
  }

}

/// 주간 마음 캔들 차트(수제). 그라데이션 몸통 + 둥근 심지 + 오늘 강조.
class _CandlePainter extends CustomPainter {
  double _yOf(double sc, double h) => (100 - sc) / 100 * h;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // 점선 가이드선 + 우측 라벨
    final gridPaint = Paint()
      ..color = const Color(0x2E836FFF)
      ..strokeWidth = 1;
    for (final (sc, label) in kGridLines) {
      final y = _yOf(sc.toDouble(), h);
      double x = 0;
      while (x < size.width - 4) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), gridPaint);
        x += 9;
      }
      tp.text = TextSpan(text: label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFFBBB3CC)));
      tp.layout();
      tp.paint(canvas, Offset(size.width - tp.width - 1, y - tp.height - 1));
    }

    final colW = size.width / kWeekCandles.length;
    for (int i = 0; i < kWeekCandles.length; i++) {
      final d = kWeekCandles[i];
      final up = d.up;
      final c1 = up ? const Color(0xFF3FD0B0) : const Color(0xFFFF7E90);
      final c2 = up ? const Color(0xFF22A892) : const Color(0xFFEF5468);
      final cx = (i + 0.5) * colW;
      final today = i == kTodayCandle;

      // 심지(둥근 끝)
      final wt = _yOf(d.h.toDouble(), h);
      final wb = _yOf(d.l.toDouble(), h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - 1.5, wt, 3, wb - wt), const Radius.circular(2)),
        Paint()..color = c2.withOpacity(0.4),
      );

      // 몸통(세로 그라데이션)
      final yo = _yOf(d.o.toDouble(), h), yc = _yOf(d.c.toDouble(), h);
      final bt = yo < yc ? yo : yc;
      final bh = (yo - yc).abs().clamp(6.0, h);
      final bodyRect = Rect.fromLTWH(cx - 7, bt, 14, bh);
      final bodyRRect = RRect.fromRectAndRadius(bodyRect, const Radius.circular(5));
      if (today) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bodyRect.inflate(3), const Radius.circular(7)),
          Paint()..color = c1.withOpacity(0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawRRect(
        bodyRRect,
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c2]).createShader(bodyRect),
      );
      if (today) {
        canvas.drawRRect(bodyRRect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) => false;
}


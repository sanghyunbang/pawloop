import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';

/// 산책 통계 (insight) — 이번 주 요약 + 주간 거리 막대그래프 + 자주 가는 곳.
class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1), end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  // 이번 주 파생 지표.
  double get _totalKm => kWeekKm.fold(0.0, (a, b) => a + b);
  int get _walkCount => kWeekKm.where((v) => v > 0).length;
  double get _avgKm => _walkCount == 0 ? 0 : _totalKm / _walkCount;
  double get _maxKm =>
      kWeekKm.fold(0.0, (a, b) => b > a ? b : a);

  /// kWalks의 place 빈도 상위 3.
  List<MapEntry<String, int>> get _topPlaces {
    final counts = <String, int>{};
    for (final w in kWalks) {
      counts[w.place] = (counts[w.place] ?? 0) + 1;
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(3).toList();
  }

  Widget _gradNum(String v, {double size = 21}) => ShaderMask(
        shaderCallback: (r) => _warm.createShader(r),
        child: Text(v, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
            children: [
              _header(),
              const SizedBox(height: 18),
              _summaryCard(),
              const SizedBox(height: 14),
              _weekChartCard(),
              const SizedBox(height: 14),
              _topPlacesCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(children: [
        // 탭이 아니라 푸시로 열렸을 때(홈 요약카드/프로필 메뉴)만 뒤로가기 표시.
        if (Navigator.of(context).canPop()) ...[
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
        ],
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('산책 통계', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: T.textPrimary)),
          SizedBox(height: 4),
          Text('우리 아이 활동 기록', style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
        ]),
        const Spacer(),
        const ProfileAvatar(size: 44),
      ]);

  // ── 이번 주 요약 ─────────────────────────────────
  Widget _summaryCard() {
    Widget cell(String value, String label) => Expanded(
          child: Column(children: [
            _gradNum(value),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0x9E463C64))),
          ]),
        );
    Widget div() => Container(width: 1, height: 38, color: const Color(0x248C7BFF));
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(children: [
        cell('${_totalKm.toStringAsFixed(1)}km', '총 거리'),
        div(),
        cell('$_walkCount회', '산책 횟수'),
        div(),
        cell('${_avgKm.toStringAsFixed(1)}km', '평균 거리'),
      ]),
    );
  }

  // ── 주간 거리 막대그래프 ─────────────────────────
  Widget _weekChartCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('주간 산책 거리', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const Spacer(),
          const Text('단위 km', style: TextStyle(fontSize: 11, color: T.textMuted)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.circle, size: 9, color: Color(0xFFFF7E8A)),
          const SizedBox(width: 5),
          const Text('오늘', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE07A4E))),
          const SizedBox(width: 12),
          Container(width: 9, height: 9, decoration: BoxDecoration(color: const Color(0x668C7BFF), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          const Text('평일', style: TextStyle(fontSize: 11, color: T.textMuted)),
        ]),
        const SizedBox(height: 16),
        SizedBox(height: 190, child: _barChart()),
      ]),
    );
  }

  Widget _barChart() {
    final maxY = (_maxKm <= 0 ? 1.0 : _maxKm) * 1.25;
    const todayColor = Color(0xFFFF7E8A);
    const otherColor = Color(0x8C9E8FE8);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xF0453C69),
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItem: (group, groupIdx, rod, rodIdx) => BarTooltipItem(
              '${kWeekDayLabels[group.x]}요일\n',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              children: [
                TextSpan(
                  text: '${rod.toY.toStringAsFixed(1)} km',
                  style: const TextStyle(color: Color(0xFFFFD9C2), fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0x1F8C7BFF), strokeWidth: 1, dashArray: [4, 5]),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                if (value <= 0.01) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10, color: T.textMuted)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= kWeekDayLabels.length) return const SizedBox.shrink();
                final today = i == kWalkTodayIdx;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    kWeekDayLabels[i],
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                      color: today ? const Color(0xFFFF7A59) : T.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < kWeekKm.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: kWeekKm[i],
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                  color: i == kWalkTodayIdx ? null : otherColor,
                  gradient: i == kWalkTodayIdx
                      ? const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFFFFA96B), todayColor],
                        )
                      : null,
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: const Color(0x0F8C7BFF),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 자주 가는 곳 ─────────────────────────────────
  Widget _topPlacesCard() {
    final top = _topPlaces;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('자주 가는 곳', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
          Spacer(),
          Text('산책 기록 기준', style: TextStyle(fontSize: 12, color: Color(0x99463C64))),
        ]),
        const SizedBox(height: 4),
        for (int i = 0; i < top.length; i++)
          _placeRow(i + 1, top[i].key, top[i].value, i < top.length - 1),
      ]),
    );
  }

  Widget _placeRow(int rank, String place, int count, bool border) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: border ? const Border(bottom: BorderSide(color: Color(0x1A8C7BFF))) : null,
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(gradient: _warm, borderRadius: BorderRadius.circular(11)),
          child: Text('$rank', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0x1AFF7E8A), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.directions_walk_rounded, size: 13, color: Color(0xFFE07A4E)),
            const SizedBox(width: 3),
            Text('$count회', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
          ]),
        ),
      ]),
    );
  }
}

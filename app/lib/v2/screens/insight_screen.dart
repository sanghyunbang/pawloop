import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../widgets/aurora.dart';
import '../widgets/walk_feed_builder.dart';
import '../data/walk_feed.dart';
import '../widgets/profile_avatar.dart';

/// 산책 통계 (insight) — 이번 주 요약 + 주간 거리 막대그래프 + 자주 가는 곳.
class InsightScreen extends StatefulWidget {
  /// 테스트에서 갈아 끼운다. 화면은 평소 기본 피드를 쓴다.
  final WalkFeed? feed;

  const InsightScreen({super.key, this.feed});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  /// 화면이 그리는 자료. [WalkFeedBuilder] 가 채운다.
  WalkFeedData _data = WalkFeedData.empty;

  /// 이번 주 요일별 거리. **전송 대기 중인 것도 얹는다** — 방금 걸었는데 막대가 안 오르면
  /// 사용자는 기록이 안 됐다고 읽는다.
  List<double> get _weekKm => _data.weekKmWithPending;

  double get _totalKm => _weekKm.fold(0.0, (a, b) => a + b);

  /// **산책 건수**다. 예전에는 `kWeekKm.where((v) => v > 0).length` 로 **산책한 날 수**를
  /// 세면서 "산책 횟수" 라고 적고 있었다 — 하루에 두 번 걸으면 1 로 나왔다.
  int get _walkCount => _data.stats.walkCount + _data.pending.length;

  double get _avgKm => _walkCount == 0 ? 0 : _totalKm / _walkCount;

  double get _maxKm => _weekKm.fold(0.0, (a, b) => b > a ? b : a);

  /// 주간 요약 문구.
  ///
  /// **하드코딩된 주장을 지웠다.** 예전 문구는 "주말에 가장 활발했고 … 서울숲 평지 코스
  /// 위주를 추천해요" 였는데, 둘 다 근거가 없었다. 실제로 화요일에만 걸은 주에도
  /// "주말에 가장 활발" 이라고 말했다(실측). 옆의 숫자가 실데이터가 되면서 그 문장이
  /// **분석처럼 읽히기 시작했다** — 더미였을 때보다 나쁘다.
  ///
  /// 지금 말하는 것은 **자료에서 나오는 것뿐**이다: 횟수·거리·평균, 그리고 가장 많이
  /// 걸은 요일. 코스 추천은 `Walk` 에 장소 축이 생기는 날 다시 본다.
  String get _weeklyReport {
    if (_walkCount == 0) {
      return '이번 주는 아직 기록이 없어요. 오늘 한 바퀴 어때요.';
    }

    final buffer = StringBuffer(
      '이번 주는 $_walkCount회 · ${_totalKm.toStringAsFixed(1)}km 걸었어요. ',
    );

    // 가장 많이 걸은 요일. 같은 값이 여럿이면 앞선 요일을 고른다 — 순위를 지어내지 않는다.
    var best = 0;
    for (var i = 1; i < _weekKm.length; i++) {
      if (_weekKm[i] > _weekKm[best]) best = i;
    }
    if (_weekKm[best] > 0) {
      buffer.write('${kWeekDayLabels[best]}요일에 가장 많이 걸었고, ');
    }

    buffer.write('평균 ${_avgKm.toStringAsFixed(1)}km 예요.');
    return buffer.toString();
  }

  /// 오늘이 몇 번째 막대인가. **월요일이 0 이다.**
  ///
  /// 예전에는 `kWalkTodayIdx = 6` 이라는 상수였다 — 무슨 요일이든 강조가 일요일에 찍혔다.
  int get _todayIndex => WalkFeedData.todayIndex;

  /// 자주 간 곳 상위.
  ///
  /// **항상 비어 있다.** 계약의 `WalkStats.topPlaces` 도 그렇고, 이유가 같다 — `Walk` 에
  /// 장소 축이 없어서 셀 근거가 없다. 예전에는 더미 `kWalks` 의 `place` 문자열을 세고
  /// 있었고, 그건 사용자가 실제로 간 곳이 아니었다.
  ///
  /// 그럴듯한 값을 만들어 넣는 대신 화면이 "아직 없다" 를 말한다.
  List<MapEntry<String, int>> get _topPlaces => const [];

  Widget _gradNum(String v, {double size = 21}) => ShaderMask(
    shaderCallback: (r) => _warm.createShader(r),
    child: Text(
      v,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => WalkFeedBuilder(
        feed: widget.feed,
        builder: (context, data, _) {
          _data = data;
          return _build(context);
        },
      );

  Widget _build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(context).padding.bottom + 100,
            ),
            children: [
              _header(),
              const SizedBox(height: 18),
              _summaryCard(),
              const SizedBox(height: 14),
              _aiReportCard(),
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

  Widget _header() => Row(
    children: [
      // 탭이 아니라 푸시로 열렸을 때(홈 요약카드/프로필 메뉴)만 뒤로가기 표시.
      if (Navigator.of(context).canPop()) ...[
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
      ],
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '산책 통계',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: T.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '우리 아이 활동 기록',
            style: TextStyle(fontSize: 13, color: Color(0xB3463C64)),
          ),
        ],
      ),
      const Spacer(),
      const ProfileAvatar(size: 44),
    ],
  );

  // ── 이번 주 요약 ─────────────────────────────────
  Widget _summaryCard() {
    Widget cell(String value, String label) => Expanded(
      child: Column(
        children: [
          _gradNum(value),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0x9E463C64)),
          ),
        ],
      ),
    );
    Widget div() =>
        Container(width: 1, height: 38, color: const Color(0x248C7BFF));
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Column(
        children: [
          Row(
            children: [
              cell('${_totalKm.toStringAsFixed(1)}km', '총 거리'),
              div(),
              cell('$_walkCount회', '산책 횟수'),
              div(),
              cell('${_avgKm.toStringAsFixed(1)}km', '평균 거리'),
            ],
          ),
          // 서버를 못 불렀는데 0 을 그냥 보여 주면 "한 번도 안 걸었다" 로 읽힌다.
          // today_screen 에는 이 규칙을 넣어 놓고 여기는 빠뜨렸었다 (#161).
          if (_data.offline && !_data.hasAnything) ...[
            const SizedBox(height: 10),
            const Text(
              '기록을 불러오지 못했어요',
              style: TextStyle(fontSize: 11.5, color: Color(0x9E463C64)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 이번 주 요약 — 규칙으로 계산한 문장이다. "AI" 라고 부르지 않는다(#332). 진짜 요약은 #359.
  Widget _aiReportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x1FFFA96B), Color(0x1AFF7E8A)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x3DFF8F63)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insights_rounded,
                size: 19,
                color: Color(0xFFE07A4E),
              ),
              const SizedBox(width: 8),
              const Text(
                '이번 주 요약',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE07A4E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            _weeklyReport,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: Color(0xD64A3F63),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '이번 주 산책 기록에서 계산했어요',
            style: TextStyle(fontSize: 11, color: T.textMuted),
          ),
        ],
      ),
    );
  }

  // ── 주간 거리 막대그래프 ─────────────────────────
  Widget _weekChartCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '주간 산책 거리',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: T.textPrimary,
                ),
              ),
              const Spacer(),
              const Text(
                '단위 km',
                style: TextStyle(fontSize: 11, color: T.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.circle, size: 9, color: Color(0xFFFF7E8A)),
              const SizedBox(width: 5),
              const Text(
                '오늘',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE07A4E),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0x668C7BFF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                '평일',
                style: TextStyle(fontSize: 11, color: T.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 190, child: _barChart()),
        ],
      ),
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
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipItem: (group, groupIdx, rod, rodIdx) => BarTooltipItem(
              '${kWeekDayLabels[group.x]}요일\n',
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              children: [
                TextSpan(
                  text: '${rod.toY.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Color(0xFFFFD9C2),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Color(0x1F8C7BFF),
            strokeWidth: 1,
            dashArray: [4, 5],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // "263m" 이 30px 에서 "263 / m" 두 줄로 꺾였다(에뮬레이터, #332). 한 줄로 못 박는다.
              reservedSize: 38,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                if (value <= 0.01) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    axisLabel(value),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(fontSize: 10, color: T.textMuted),
                  ),
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
                if (i < 0 || i >= kWeekDayLabels.length) {
                  return const SizedBox.shrink();
                }
                final today = i == _todayIndex;
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
          for (int i = 0; i < _weekKm.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _weekKm[i],
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                  color: i == _todayIndex ? null : otherColor,
                  gradient: i == _todayIndex
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                '자주 가는 곳',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: T.textPrimary,
                ),
              ),
              Spacer(),
              Text(
                '산책 기록 기준',
                style: TextStyle(fontSize: 12, color: Color(0x99463C64)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 지금은 늘 비어 있다(`_topPlaces`). 빈 카드로 두면 고장처럼 보인다(#332).
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '아직 없어요 · 산책에 장소가 붙으면 여기 쌓여요',
                style: TextStyle(fontSize: 12.5, color: T.textMuted),
              ),
            ),
          for (int i = 0; i < top.length; i++)
            _placeRow(i + 1, top[i].key, top[i].value, i < top.length - 1),
        ],
      ),
    );
  }

  Widget _placeRow(int rank, String place, int count, bool border) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: border
            ? const Border(bottom: BorderSide(color: Color(0x1A8C7BFF)))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _warm,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: T.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x1AFF7E8A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.directions_walk_rounded,
                  size: 13,
                  color: Color(0xFFE07A4E),
                ),
                const SizedBox(width: 3),
                Text(
                  '$count회',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE07A4E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 세로축 한 눈금. 1km 미만은 m 로, 그 위는 소수 첫째 자리 — 정수로 반올림하면 0.15km 한 건일
/// 때 눈금이 "0 0 0 0" 이었다(#332).
String axisLabel(double km) {
  if (km < 1) return '${(km * 1000).round()}m';
  return km.toStringAsFixed(1);
}

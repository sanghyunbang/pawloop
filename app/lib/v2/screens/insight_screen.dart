import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_tokens.dart';
import '../domain/pet.dart';
import '../domain/walk_goal.dart';
import '../domain/weekly_summary.dart';
import '../data/walk_goal_store.dart';
import '../widgets/aurora.dart';
import '../widgets/walk_feed_builder.dart';
import '../data/walk_feed.dart';
import '../data/walk_repository.dart';
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
    colors: [T.warmStart, T.warmEnd],
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

  /// 이 아이의 주간 목표 — 달성률 줄에 쓴다. 기기에 있는 값이라 서버가 모른다(#341).
  ///
  /// **개가 아니면 `null` 이다.** 산책 권장량은 개에 대한 자료다(`WalkGoal.recommendedFor`).
  /// 그때는 달성률 줄이 아예 없다 — 근거 없는 숫자를 목표라고 부르지 않는다.
  WalkGoal? _goal;

  @override
  void initState() {
    super.initState();
    _loadGoal();
  }

  Future<void> _loadGoal() async {
    final pet = kMyDog.value;
    if (pet == null) return;
    final saved = await const WalkGoalStore().read(petId: pet.serverId);
    if (!mounted) return;
    setState(() => _goal = saved ??
        WalkGoal.recommendedFor(
          species: pet.species,
          size: pet.size,
          ageMonths: pet.ageMonths,
        ));
  }

  /// 주간 요약 — 이슈 #359 1단계. **규칙으로 계산한다.**
  ///
  /// 예전에는 여기서 문자열을 조립했다: "이번 주는 3회 · 6.2km 걸었어요. 화요일에 가장
  /// 많이 걸었고, 평균 2.1km 예요." 사실이지만 **아무것도 말해 주지 않는다** — 사용자가
  /// 이미 옆의 막대에서 읽은 숫자를 문장으로 다시 적은 것뿐이다.
  ///
  /// 지금은 셋을 더한다: 우리 아이 기준 목표 대비 · 빠진 요일 · 지난주 대비. 그리고 하나를
  /// 제안한다. 계산은 [WeeklySummary] 한 곳에 있다 — 화면은 그 결과를 그리기만 한다.
  ///
  /// LLM 두 문장은 2단계이고 키가 필요하다(#359). 그때까지 이 자리는 **"AI" 라고 부르지
  /// 않는다**(#332).
  WeeklySummary get _summary => WeeklySummary.of(
        walkCount: _walkCount,
        totalKm: _totalKm,
        weekKm: _weekKm,
        weekMinutes: _data.stats.weekMinutes,
        summary: _data.stats.summary,
        goal: _goal,
      );

  /// 오늘이 몇 번째 막대인가. **월요일이 0 이다.**
  ///
  /// 예전에는 `kWalkTodayIdx = 6` 이라는 상수였다 — 무슨 요일이든 강조가 일요일에 찍혔다.
  int get _todayIndex => WalkFeedData.todayIndex;

  /// 자주 간 곳 상위 — 서버가 센 값이다 (#338).
  ///
  /// **카탈로그에서 고른 곳만 들어온다.** 저장 화면에서 이름을 손으로 적으면 그 기록에는
  /// 남지만 여기에는 안 온다 — 서버가 계약의 `PlaceRef`(출처·id)를 만들 수 없어서다.
  /// 예전에는 더미 `kWalks` 의 문자열을 세고 있었고, 그건 사용자가 간 곳이 아니었다.
  List<WalkTopPlace> get _topPlaces => _data.stats.topPlaces;

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
      backgroundColor: T.bgTop,
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
              color: T.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: T.cardBorder),
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
            style: TextStyle(fontSize: 13, color: T.textSecondary),
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
            style: const TextStyle(fontSize: 12, color: T.textMuted),
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
              style: TextStyle(fontSize: 11.5, color: T.textMuted),
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
          colors: [Color(0x1FFFA96B), T.warmSoft],
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
                color: T.warmText,
              ),
              const SizedBox(width: 8),
              const Text(
                '이번 주 요약',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: T.warmText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            _summary.text,
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
              const Icon(Icons.circle, size: 9, color: T.warmEnd),
              const SizedBox(width: 5),
              const Text(
                '오늘',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.warmText,
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
    const todayColor = T.warmEnd;
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
                    color: T.glowStart,
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
            color: T.line,
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
                          colors: [T.warmStart, todayColor],
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
                style: TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 비어 있으면 빈 카드로 두지 않고 무엇을 하면 쌓이는지 말한다(#332 · #338).
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '아직 없어요 · 산책을 저장할 때 장소를 고르면 여기 쌓여요',
                style: TextStyle(fontSize: 12.5, color: T.textMuted),
              ),
            ),
          for (int i = 0; i < top.length; i++)
            _placeRow(i + 1, top[i].place.title, top[i].count, i < top.length - 1),
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
              color: T.warmSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.directions_walk_rounded,
                  size: 13,
                  color: T.warmText,
                ),
                const SizedBox(width: 3),
                Text(
                  '$count회',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: T.warmText,
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

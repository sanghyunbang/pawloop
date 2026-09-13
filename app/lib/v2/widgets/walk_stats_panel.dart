// lib/v2/widgets/walk_stats_panel.dart
//
// 트래킹 화면 아래의 스탯 패널 — 거리·시간·페이스와 일시정지·종료.
//
// ## 왜 기본이 펼침인가 (#327)
//
// 예전엔 기본이 접힘이라 화면에는 "0.11km · 00:18 ^" 알약만 있었고, 산책 중 가장
// 필요한 버튼(종료)은 한 번 더 눌러야 나왔다. 걷는 사람은 줄과 배변봉투를 들고 있다.
// 주 동작은 첫 프레임부터 보여야 하고, 접는 것은 지도를 크게 보고 싶은 사람이 고른다.
//
// 트래킹 화면(`walk_tracking_screen.dart`)의 상태 메서드였던 것을 떼어 낸 이유는
// 그 화면이 실 GPS 와 지도 SDK 를 끌고 와서 위젯 테스트로 세울 수 없기 때문이다 —
// 여기서는 "펼침이면 종료가 보인다" 를 화면 없이 잰다.
//
// ## 숫자 세 칸은 완료 시트와 한 벌이다 (#386)
//
// 거리·시간·페이스는 `WalkSummaryRow` 가 그린다 — 산책 완료 시트도 같은 것을 쓴다.
// 왜 재서 줄이는지는 `walk_summary_row.dart` 머리말에 있다. 여기 있던 `_stat` 은
// `Row(spaceAround)` 에 얹혀 있어 360dp 에서 68px, 393dp 에서도 35px 넘쳤다.
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'walk_summary_row.dart';

class WalkStatsPanel extends StatelessWidget {
  const WalkStatsPanel({
    super.key,
    required this.km,
    required this.timeLabel,
    required this.paceLabel,
    required this.paused,
    required this.expanded,
    required this.onToggle,
    required this.onPauseToggle,
    required this.onFinish,
    this.bottomInset = 0,
  });

  /// 트래킹 화면이 처음 그릴 때의 펼침 여부. **펼침** — 위 머리말.
  static const bool expandedByDefault = true;

  /// 이 배율부터 보조 안내("실시간 GPS")를 접는다.
  ///
  /// 1.3 은 홈의 두 버튼이 위아래로 서는 지점과 같은 값이다(#396) — 화면마다 다른 문턱을
  /// 두면 같은 배율에서 어떤 곳은 접히고 어떤 곳은 안 접혀 사용자가 규칙을 못 읽는다.
  static const double _hideHintFrom = 1.3;

  /// 이 배율부터 **장식을 접는다** — 머리말의 보조 안내와 두 버튼의 아이콘.
  ///
  /// 아이콘을 먼저 접는 이유: 버튼이 무엇을 하는지는 <b>글자</b>가 말한다. 320dp·2.0배에서
  /// 아이콘(21px)과 간격(6px)이 27px 을 먹고, 그것이 정확히 넘치던 폭이었다(17px 넘침).
  /// 글자를 줄이거나 자르면 "일시…" 가 되어 무엇을 누르는지 알 수 없다.
  ///
  /// 글자도 [Flexible] 로 감싼 것은 **바닥**이다 — 더 긴 말이 들어오거나 더 좁은 기기가
  /// 나와도 노란 줄무늬 대신 말줄임으로 끝난다.
  static bool _hideHint(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11) >= 11 * _hideHintFrom;

  final double km;
  final String timeLabel;
  final String paceLabel;
  final bool paused;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPauseToggle;
  final VoidCallback onFinish;
  final double bottomInset;

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  Color get _dot => paused ? T.textFaint : T.warmEnd;

  @override
  Widget build(BuildContext context) {
    if (!expanded) return _pill();
    return _expanded(context);
  }

  /// 접힘: 작은 알약 — 상태·거리·시간. 탭하면 펼침.
  Widget _pill() {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: EdgeInsets.only(bottom: bottomInset + 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: T.barShadow, blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _dot),
            ),
            const SizedBox(width: 8),
            // 알약은 한 줄짜리라 나눌 칸이 없다 — 안 들어가면 그대로 줄인다.
            // `Flexible` 이 없으면 Row 가 이 글자에 폭을 무한대로 주고, 값이 길거나 기기
            // 글자 크기가 크면 노란 줄무늬가 된다(360dp·1.5배·`12.24km · 120:45` 에서 54px).
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${km.toStringAsFixed(2)}km · $timeLabel',
                  maxLines: 1,
                  softWrap: false,
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: T.textMuted),
          ],
        ),
      ),
    );
  }

  /// 펼침: 큰 스탯 + 일시정지/종료.
  Widget _expanded(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 14),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: T.barShadow, blurRadius: 26, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _dot),
                ),
                const SizedBox(width: 6),
                // `Spacer` 를 겸한다 — 남는 폭을 먹고, **모자라면 이것이 줄어든다.**
                // 예전에는 이 자리가 flex 가 아닌 `Text` + `Spacer` 였다. Row 는 flex 가
                // 아닌 자식에게 폭을 무한대로 주므로 두 글자의 합이 Row 를 넘었고,
                // `Spacer` 는 남은 공간이 음수여도 0 까지만 줄어든다 — 글자 2.0배 ·
                // 360dp 에서 75px 넘쳤다(#402 실측).
                Expanded(
                  child: Text(
                    paused ? '일시정지됨' : '산책 기록 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: paused ? T.textMuted : T.warmText,
                    ),
                  ),
                ),
                // 이 패널은 실 GPS 로 트래킹 중일 때만 뜬다 — 위치가 없으면 지도
                // 자체가 만들어지지 않는다. 그래서 이 줄은 **보조 안내**다.
                //
                // 글자를 키운 사람에게는 접는다. `Expanded` 만으로도 안 넘치지만, 그러면
                // 상태("산책 기록 중")가 "산…" 으로 잘린다 — 지금 기록 중인지 멈췄는지가
                // 이 줄에서 가장 중요한 정보다. 보조를 먼저 접어 그 자리를 지킨다.
                if (!_hideHint(context)) ...[
                  const Text('실시간 GPS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: T.textMuted)),
                  const SizedBox(width: 4),
                ],
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: T.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WalkSummaryRow(
            [
              (km.toStringAsFixed(2), 'km'),
              (timeLabel, '시간'),
              (paceLabel, '페이스'),
            ],
            valueSize: 24,
            labelSize: 11.5,
            gap: 2,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onPauseToggle,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_hideHint(context)) ...[
                          Icon(
                            paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                            size: 21,
                            color: T.textSecondary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            paused ? '재개' : '일시정지',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onFinish,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _warm,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_hideHint(context)) ...[
                          const Icon(Icons.stop_rounded, size: 21, color: Colors.white),
                          const SizedBox(width: 6),
                        ],
                        const Flexible(
                          child: Text(
                            '종료',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

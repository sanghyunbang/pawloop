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
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

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
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  Color get _dot => paused ? const Color(0xFFBBB3CC) : const Color(0xFFFF7E8A);

  @override
  Widget build(BuildContext context) {
    if (!expanded) return _pill();
    return _expanded();
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
            BoxShadow(color: Color(0x2E5A4690), blurRadius: 18, offset: Offset(0, 8)),
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
            Text(
              '${km.toStringAsFixed(2)}km · $timeLabel',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: T.textPrimary),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: T.textMuted),
          ],
        ),
      ),
    );
  }

  /// 펼침: 큰 스탯 + 일시정지/종료.
  Widget _expanded() {
    return Container(
      margin: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 14),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x2E5A4690), blurRadius: 26, offset: Offset(0, 10)),
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
                Text(
                  paused ? '일시정지됨' : '산책 기록 중',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: paused ? T.textMuted : const Color(0xFFE07A4E),
                  ),
                ),
                const Spacer(),
                // 이 패널은 실 GPS 로 트래킹 중일 때만 뜬다 — 위치가 없으면 지도
                // 자체가 만들어지지 않는다.
                const Text('실시간 GPS', style: TextStyle(fontSize: 11, color: T.textMuted)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: T.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(km.toStringAsFixed(2), 'km'),
              _stat(timeLabel, '시간'),
              _stat(paceLabel, '페이스'),
            ],
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
                      color: const Color(0xFFF1ECF7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 21,
                          color: T.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          paused ? '재개' : '일시정지',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stop_rounded, size: 21, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          '종료',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
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

  Widget _stat(String v, String label) => Column(
        children: [
          Text(
            v,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0x9E463C64))),
        ],
      );
}

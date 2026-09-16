// lib/v2/widgets/walk_moment_bar.dart
//
// 산책 중 한 손 기록 — 배변 · 마킹 · 물 세 버튼 (#340).
//
// ## 왜 화면 아래인가
//
// 한 손에는 줄이 있다. 남은 손의 엄지가 닿는 곳은 화면 아래쪽이라 이 줄은 **스탯 패널
// 바로 위**에 붙는다. 버튼 하나의 높이는 56 이상이다 — 걸으면서 누르는 것이라 정지해서
// 누르는 것보다 넉넉해야 한다.
//
// ## 왜 시스템 이모지가 아닌가
//
// 💩·💧 는 기기마다 다른 그림이고 어떤 기기에서는 흑백 네모로 나온다. 배변과 마킹은
// [_MomentGlyph] 가 직접 그리고, 물은 앱이 이미 케어 카드에서 쓰는 물방울 아이콘을
// 그대로 쓴다 — 같은 뜻에 그림이 둘이면 사용자가 다른 것으로 읽는다.
//
// ## 취소
//
// 누르면 바로 기록이다. 확인을 묻지 않는다 — 확인이 붙는 순간 한 탭이 두 탭이 된다.
// 대신 **5초 안에 같은 버튼을 다시 누르면 취소**하고, 그동안 버튼 아래에 그 말을 적어 둔다.
import 'package:flutter/material.dart';

import '../domain/walk_moment.dart';
import 'care_glyph.dart';
import '../theme/app_tokens.dart';

class WalkMomentBar extends StatelessWidget {
  const WalkMomentBar({
    super.key,
    required this.tally,
    required this.onTap,
    this.undoable,
    this.trailing,
  });

  /// 순간 버튼들 뒤에 하나 더 — 산책 중 카메라(#450). 같은 칸 폭을 나눠 쓴다. 없으면 셋뿐이다.
  final Widget? trailing;

  /// 지금까지의 횟수. 0 이면 배지를 안 그린다.
  final WalkMomentTally tally;

  /// 눌린 종류를 준다. 기록할지 취소할지는 **화면이** 정한다 — 이 위젯은 창구다.
  final void Function(WalkMomentKind kind) onTap;

  /// 5초 창이 열려 있는 종류. 그 버튼만 "다시 누르면 취소" 를 보여 준다.
  final WalkMomentKind? undoable;

  /// 한 손 엄지로 누르는 버튼의 최소 크기. 손가락 권장치(48)보다 크게 잡는다.
  static const double minTapSize = 56;

  static const Map<WalkMomentKind, Color> _colors = {
    WalkMomentKind.poop: Color(0xFF9C6B4A),
    WalkMomentKind.pee: Color(0xFFD9A02B),
    WalkMomentKind.water: Color(0xFF3E9AD6),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x225A4690), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          for (final kind in WalkMomentKind.values) Expanded(child: _button(kind)),
          if (trailing != null) Expanded(child: trailing!),
        ],
      ),
    );
  }

  Widget _button(WalkMomentKind kind) {
    final color = _colors[kind]!;
    final count = tally[kind];
    final undo = undoable == kind;

    return Semantics(
      button: true,
      label: undo ? '${kind.label} 취소' : kind.label,
      child: GestureDetector(
        onTap: () => onTap(kind),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: minTapSize),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: undo ? color : color.withValues(alpha: 0.12),
                    ),
                    child: _MomentGlyph(
                      kind: kind,
                      color: undo ? Colors.white : color,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: -4,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                undo ? '다시 누르면 취소' : kind.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: undo ? 10 : 12,
                  fontWeight: FontWeight.w700,
                  color: undo ? color : T.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 세 그림. 배변·마킹은 직접 그리고 물은 앱이 이미 쓰는 아이콘을 쓴다.
class _MomentGlyph extends StatelessWidget {
  const _MomentGlyph({required this.kind, required this.color});

  final WalkMomentKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (kind) {
        WalkMomentKind.water => Icon(Icons.water_drop_rounded, size: 20, color: color),
        // **케어 카드와 같은 그림이다**(`care_glyph.dart`). 예전에는 이 파일이 직접 그리고
        // 카드는 머티리얼 아이콘을 써서, 같은 뜻에 그림이 둘이었다 — 이 파일 머리말이
        // 하지 말라고 적어 둔 바로 그것이다.
        WalkMomentKind.poop => CustomPaint(
            size: const Size(21, 21),
            painter: CarePoopPainter(color),
          ),
        WalkMomentKind.pee => CustomPaint(
            size: const Size(21, 21),
            painter: CarePeePainter(color),
          ),
      };
}

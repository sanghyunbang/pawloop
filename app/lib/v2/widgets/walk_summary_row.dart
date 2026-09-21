// lib/v2/widgets/walk_summary_row.dart
//
// 산책 숫자 세 칸 — 시간·거리·페이스. 트래킹 중 스탯 패널(`walk_stats_panel.dart`)과
// 산책 완료 시트(`walk_finish_sheet.dart`)가 **같은 것**을 쓴다.
//
// ## 왜 재서 줄이나 (#386)
//
// 둘 다 `Row(spaceAround)` 에 칸을 그냥 얹고 있었다. Row 는 flex 가 아닌 자식에게 **폭을
// 무한대로** 주므로 값이 제 길이만큼 자라고, 그 합이 Row 폭을 넘으면 노란 줄무늬가 뜬다.
//
// | | 360dp | 320dp |
// |---|---|---|
// | 완료 시트 (20pt) | 24px | 64px |
// | 스탯 패널 (24pt) | 68px | 393dp 에서도 35px |
//
// 값은 길이가 고정이 아니다. 시간은 두 시간을 넘기면 `120:45`, 거리는 `12.24km`,
// 페이스는 아직 못 잰 동안 `-'--"` 다. 그래서 패딩이나 칸 간격을 좁히는 것으로는 못 막는다 —
// 한 기기에서만 맞고 값이 길어지면 다시 터진다. 칸을 정확히 1/3 로 나눠 넘침 자체를 없애고
// (`Expanded` 는 자식에게 꽉 찬 폭을 준다 — 넘치는 대신 글자가 제 안에서 처리된다),
// 그 폭에 안 들어갈 때만 글자를 줄인다.
//
// ## 세 칸이 **같은 크기**로 줄어든다
//
// 칸마다 `FittedBox` 를 하나씩 두면 짧은 값은 제 크기로 남고 긴 값만 작아져 한 줄에 크기가
// 섞인다. 나란히 놓인 숫자는 같은 크기여야 한눈에 견줄 수 있으므로, 가장 긴 값 하나로
// 배율을 정해 셋에 같이 먹인다.
//
// ## 왜 한 벌인가
//
// 처음엔 완료 시트만 고쳤다(#386 · PR #387). 같은 알고리즘을 패널에 한 벌 더 두면, 다음에
// 누가 한쪽만 고치고 다른 쪽을 두고 간다 — 이 버그가 애초에 두 곳에 같이 있었던 이유가
// 그것이다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class WalkSummaryRow extends StatelessWidget {
  /// (값, 라벨) 쌍. 보통 시간·거리·페이스 셋이다.
  final List<(String, String)> cells;

  /// 넓은 화면에서 쓰는 값 글자 크기 — 여기서부터 줄어들 뿐, 넘어서 커지지는 않는다.
  /// 완료 시트 20 · 스탯 패널 24.
  final double valueSize;

  /// 라벨 글자 크기. 라벨은 값보다 훨씬 짧아 줄일 일이 없다 — 넘쳐도 `Text` 가 제 안에서
  /// 처리하므로 줄무늬가 되지 않는다.
  final double labelSize;

  /// 값과 라벨 사이.
  final double gap;

  /// 눌러서 설명을 볼 수 있는 칸 — 칸 번호에서 할 일로.
  ///
  /// 그 칸의 라벨 옆에 작은 ⓘ 가 붙고 라벨 줄 전체가 눌린다. **낱말을 늘려 설명하려던 것을
  /// 되돌린 자리다**(2026-09-21): `페이스(1km)` 는 1km 가 시간인지 거리인지 안 말해 줘서
  /// 오히려 더 헷갈린다는 지적을 받았다. 짧은 이름은 그대로 두고 설명은 눌렀을 때 준다.
  final Map<int, VoidCallback> explain;

  const WalkSummaryRow(
    this.cells, {
    super.key,
    required this.valueSize,
    this.labelSize = 12,
    this.gap = 3,
    this.explain = const {},
  });

  static const Color labelColor = T.textMuted;

  TextStyle _valueStyle(double size) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: T.textPrimary);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final size = _sizeThatFits(context, box.maxWidth / cells.length);
          return Row(
            children: [
              for (final (i, (value, label)) in cells.indexed)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: _valueStyle(size),
                      ),
                      SizedBox(height: gap),
                      _label(label, explain[i]),
                    ],
                  ),
                ),
            ],
          );
        },
      );

  /// 칸 이름. 설명이 딸린 칸은 ⓘ 가 붙고 눌린다.
  Widget _label(String label, VoidCallback? onTap) {
    final text = Text(
      label,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: labelSize, color: labelColor),
    );
    if (onTap == null) return text;
    return GestureDetector(
      key: Key('explain-$label'),
      onTap: onTap,
      // 글자만 누르면 잘 안 눌린다 — 라벨 줄 높이만큼 눌리는 영역을 준다.
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: text),
          const SizedBox(width: 2),
          Icon(Icons.help_outline_rounded, size: labelSize + 1.5, color: labelColor),
        ],
      ),
    );
  }

  /// 한 칸 폭 안에 세 값이 **모두** 들어가는 글자 크기. 다 들어가면 [valueSize] 그대로다.
  ///
  /// 테마 폰트(Pretendard)와 기기 글자 크기 배율까지 실제로 그릴 때와 같게 재야 한다 —
  /// 기본 스타일을 빼고 재면 폭을 잘못 잡아 다시 넘친다.
  double _sizeThatFits(BuildContext context, double cellWidth) {
    // 가로가 무한한 곳(가로 스크롤 등)에 놓이면 잴 것이 없다 — 원래 크기로 둔다.
    if (!cellWidth.isFinite || cellWidth <= 0) return valueSize;
    final base = DefaultTextStyle.of(context).style.merge(_valueStyle(valueSize));
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final (value, _) in cells) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: base),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    // 딱 맞게 줄이면 반올림 한 픽셀에 끝 글자가 잘린다. 1px 을 남긴다.
    final room = cellWidth - 1;
    if (widest <= room || widest == 0) return valueSize;
    return valueSize * room / widest;
  }
}

/// 페이스 값(`4'35"`)을 사람 말로 — `4분 35초`. 못 잰 값(`-'--"`)이면 `null`.
///
/// 화면에 쓰는 표기는 달리기 앱의 관례라 짧지만, 처음 보는 사람에게는 읽히지 않는다.
/// 설명 안에서는 풀어 쓴다.
String? paceInWords(String paceLabel) {
  final m = RegExp(r"^(\d+)'(\d{1,2})\x22?$").firstMatch(paceLabel.trim());
  if (m == null) return null;
  return '${m.group(1)}분 ${int.parse(m.group(2)!)}초';
}

/// "페이스가 뭔가요?" — 눌렀을 때 뜨는 설명.
///
/// **낱말을 늘리는 것으로는 안 됐다**(2026-09-21). 라벨을 `페이스(1km)` 로 바꿔 봤더니
/// 그 1km 가 시간인지 거리인지 안 말해 줘서 더 헷갈린다는 지적을 받았다. 지금 화면에 떠
/// 있는 값을 그대로 들어 "이 숫자가 이런 뜻이다" 라고 말하는 편이 짧고 확실하다.
Future<void> showPaceExplanation(BuildContext context, String paceLabel) {
  final words = paceInWords(paceLabel);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      key: const Key('pace-explainer'),
      backgroundColor: T.surfaceBright,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('페이스가 뭔가요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1km 를 걷는 데 걸리는 시간이에요.',
              style: TextStyle(
                  fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
          const SizedBox(height: 8),
          Text(
            words == null
                ? '아직 거리가 짧아 못 재고 있어요. 조금 더 걸으면 나와요.'
                : "지금 $paceLabel 은 1km 를 $words 에 걷고 있다는 뜻이에요.",
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text('빨리 걸을수록 숫자가 작아져요.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('알겠어요',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText)),
        ),
      ],
    ),
  );
}

// 케어 항목의 그림 한 자리 — 이슈 #560.
//
// ## 왜 이 파일이 생겼나
//
// 배변·마킹을 **산책 바와 케어 카드가 서로 다른 그림으로** 그리고 있었다. 산책 바는 직접
// 그린 글리프(💩 모양·물방울+바닥선)를 쓰고, 카드는 머티리얼 아이콘(잎사귀·물방울)을 썼다.
// 그 파일이 스스로 적어 둔 규칙이 "같은 뜻에 그림이 둘이면 사용자가 다른 것으로 읽는다"
// 인데, 카드가 그 규칙을 어기고 있었다 — 에뮬레이터에서 보고 찾았다.
//
// 게다가 카드의 마킹(`Icons.opacity`)은 물(`Icons.water_drop`)과 거의 같은 물방울이라, 둘 다
// 아직인 날에는 나란히 같은 그림 둘이 앉는다. 직접 그린 마킹에는 **바닥선**이 있어 물과
// 눈으로 갈린다 — 그래서 그쪽이 맞다.
//
// 이제 그림을 내는 자리는 [CareGlyph] 하나다.
import 'package:flutter/material.dart';

import '../domain/care_icons.dart';

/// 항목의 그림. 열쇠말로 고르고, **모르는 값이면 기본 그림**이다.
///
/// 배변·마킹만 직접 그린다 — 머티리얼에 그 뜻의 아이콘이 없고, 비슷한 것을 골라 두면
/// 산책 바의 그림과 갈린다.
class CareGlyph extends StatelessWidget {
  const CareGlyph({
    super.key,
    required this.iconKey,
    required this.size,
    required this.color,
  });

  final String iconKey;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (iconKey) {
        'poop' => CustomPaint(size: Size(size, size), painter: CarePoopPainter(color)),
        'pee' => CustomPaint(size: Size(size, size), painter: CarePeePainter(color)),
        _ => Icon(careItemIcon(iconKey), size: size, color: color),
      };
}

/// 세 덩이를 쌓은 모양. 이모지의 그 그림을 단순한 원 셋으로 옮긴 것이다.
///
/// 💩 를 그대로 쓰지 않는 이유는 기기마다 다른 그림이고 어떤 기기에서는 흑백 네모로
/// 나오기 때문이다(`walk_moment_bar` 머리말).
class CarePoopPainter extends CustomPainter {
  const CarePoopPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width, h = size.height;
    canvas.drawOval(Rect.fromLTWH(w * 0.08, h * 0.60, w * 0.84, h * 0.34), paint);
    canvas.drawOval(Rect.fromLTWH(w * 0.20, h * 0.33, w * 0.60, h * 0.30), paint);
    canvas.drawOval(Rect.fromLTWH(w * 0.33, h * 0.10, w * 0.34, h * 0.26), paint);
  }

  @override
  bool shouldRepaint(CarePoopPainter old) => old.color != color;
}

/// 물방울 하나와 그 아래 바닥선. **물(물방울만)과 눈으로 갈린다.**
class CarePeePainter extends CustomPainter {
  const CarePeePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width, h = size.height;

    final drop = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..cubicTo(w * 0.86, h * 0.42, w * 0.80, h * 0.68, w * 0.5, h * 0.68)
      ..cubicTo(w * 0.20, h * 0.68, w * 0.14, h * 0.42, w * 0.5, h * 0.06)
      ..close();
    canvas.drawPath(drop, paint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.16, h * 0.82, w * 0.68, h * 0.10),
        Radius.circular(h * 0.05),
      ),
      Paint()..color = color.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(CarePeePainter old) => old.color != color;
}

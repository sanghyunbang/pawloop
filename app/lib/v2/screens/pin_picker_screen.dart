import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 다녀온 위치 찍기 (pinPicker) — 스타일라이즈드 지도 탭 → 좌표 기록.
/// 확인 시 Navigator.pop('내가 찍은 위치').
class PinPickerScreen extends StatefulWidget {
  const PinPickerScreen({super.key});
  @override
  State<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends State<PinPickerScreen> {
  double? dropX; // 0~1
  double? dropY;
  double? lat;
  double? lng;

  bool get _has => lat != null;

  void _drop(Offset local, Size size) {
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      dropX = x;
      dropY = y;
      lat = 37.58 - y * 0.085;
      lng = 126.96 + x * 0.11;
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFFEDE7F6),
      body: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return Stack(children: [
          // 지도 배경 + 탭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _drop(d.localPosition, size),
              child: CustomPaint(painter: _MapBgPainter(), size: Size.infinite),
            ),
          ),
          // 색 띠
          _band(top: 0.30, h: 64, color: const Color(0x52FFC88C), deg: -11, w: c.maxWidth),
          _band(top: 0.57, h: 40, color: const Color(0x4D96C3FF), deg: 7, w: c.maxWidth),
          Positioned(
            top: 0, left: c.maxWidth * 0.62, width: 46, height: c.maxHeight * 1.2,
            child: Transform.rotate(angle: 9 * math.pi / 180, child: Container(color: const Color(0x57AAE1C8))),
          ),
          // 드롭 핀
          if (_has)
            Positioned(
              left: dropX! * c.maxWidth - 21,
              top: dropY! * c.maxHeight - 42,
              child: const IgnorePointer(
                child: Icon(Icons.location_on, size: 42, color: Color(0xFFFF566E),
                    shadows: [Shadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 4))]),
              ),
            ),
          // 헤더
          Positioned(
            top: topPad + 8, left: 16, right: 16,
            child: Row(children: [
              _chip(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                pad: const EdgeInsets.all(9),
              ),
              const SizedBox(width: 12),
              _chip(
                child: const Text('다녀온 위치 찍기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary)),
                pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ]),
          ),
          // 중앙 안내 (탭 통과)
          if (!_has)
            IgnorePointer(
              child: Align(
              alignment: const Alignment(0, -0.05),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xEBFFFFFF),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x335A4682), blurRadius: 26, offset: Offset(0, 10))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.touch_app, size: 20, color: Color(0xFFFF7A59)),
                  SizedBox(width: 7),
                  Text('지도를 눌러 위치를 찍어주세요', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
                ]),
              ),
            )),
          // 하단 패널
          Positioned(
            left: 16, right: 16, bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xF7FCFAFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xD9FFFFFF)),
                boxShadow: const [BoxShadow(color: Color(0x38281E46), blurRadius: 40, offset: Offset(0, 16))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_has) ...[
                  Row(children: [
                    const Icon(Icons.my_location, size: 20, color: Color(0xFFFF566E)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('내가 찍은 위치', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
                        const SizedBox(height: 2),
                        Text('위도 ${lat!.toStringAsFixed(5)} · 경도 ${lng!.toStringAsFixed(5)}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0x99463C64))),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 13),
                ],
                GestureDetector(
                  onTap: _has ? () => Navigator.of(context).pop('내가 찍은 위치') : null,
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _has ? const LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.7, 1), colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]) : null,
                      color: _has ? null : const Color(0x29785AA0),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _has ? const [BoxShadow(color: Color(0x73D89BFF), blurRadius: 30, offset: Offset(0, 14))] : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check, size: 19, color: _has ? Colors.white : T.textMuted),
                      const SizedBox(width: 8),
                      Text('이 위치로 기록하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _has ? Colors.white : T.textMuted)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _band({required double top, required double h, required Color color, required double deg, required double w}) {
    return Positioned(
      top: MediaQuery.of(context).size.height * top,
      left: -w * 0.12,
      width: w * 1.3,
      height: h,
      child: Transform.rotate(angle: deg * math.pi / 180, child: Container(color: color)),
    );
  }

  Widget _chip({required Widget child, required EdgeInsets pad, VoidCallback? onTap}) {
    final box = Container(
      padding: pad,
      decoration: BoxDecoration(
        color: const Color(0xE0FFFFFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xD9FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x295A4682), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

/// 스타일라이즈드 지도 배경: 격자 + 라디알 블롭 + 베이스 그라데이션.
class _MapBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 베이스
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEDE7F6), Color(0xFFE6F0EA)]).createShader(rect));
    // 라디알 블롭
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(center: const Alignment(-0.44, -0.64), radius: 1.0, colors: [const Color(0xFFECE5F8), const Color(0xFFECE5F8).withOpacity(0)]).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..shader = RadialGradient(center: const Alignment(0.64, 0.64), radius: 0.9, colors: [const Color(0xFFE2F0EA), const Color(0xFFE2F0EA).withOpacity(0)]).createShader(rect));
    // 격자 (46px)
    final grid = Paint()..color = const Color(0x0F7867EB)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

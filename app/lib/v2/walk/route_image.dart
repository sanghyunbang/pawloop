// lib/v2/walk/route_image.dart
//
// 산책 경로를 **타일 없이** 그린다 — 이슈 #310 (A안 빌드의 "지도 위 루틴 + 사진").
//
// ## 왜 지도가 아닌가
//
// 네이버 지도 위에 그리면 카메라 궤적이 곧 경로라 좌표가 네이버에 간다(#235 C1). A안 빌드는
// 지도 키 없이 나가므로 산책 화면에 지도 자체가 없다 — 그러면 "내가 걸은 길" 을 눈으로 볼
// 방법이 없고, 사진으로 남길 방법도 없다. 그래서 여기서는 좌표를 **기기 안에서** 화면 좌표로
// 바꿔 폴리라인만 그린다. 배경은 타일이 아니라 단색과 옅은 격자다.
//
// ## 여기에는 네트워크가 없다
//
// 이 파일과 `route_photo_saver.dart` 는 `AuthedClient`·`package:http` 를 import 하지 않는다.
// 좌표가 이 파일을 지나 어디로도 가지 않는다는 것을 `route_photo_no_network_test.dart` 가
// 소스로 잠근다. 좌표는 트래킹 화면이 메모리에 든 것을 그대로 받는다 — 새로 GPS 를 켜지 않는다.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

import '../domain/walk_moment.dart';

/// 경도·위도 목록을 그림 안의 점으로 옮긴다. 순수 함수라 따로 잰다.
///
/// 계약과 초안 큐가 쓰는 순서 그대로 **`[경도, 위도]`** 를 받는다 — `WalkDraft.path` 와 같다.
/// 위도에 따라 경도 1도의 실제 길이가 달라지므로(서울에서 약 0.79 배) `cos(위도)` 로 경도를
/// 눌러 모양이 찌그러지지 않게 한다. 이 정도 크기(동네 산책)에서는 그 보정이면 충분하다.
class RouteProjection {
  /// [box] 안에 [padding] 을 두고 경로를 꽉 채운다. 가로세로 비율은 지킨다(등방 확대).
  ///
  /// 점이 하나뿐이거나 경로의 폭이 0 이면 상자 가운데에 놓는다 — 나눗셈이 0 이 되는 자리를
  /// 여기서 막는다.
  static List<Offset> fit(List<List<double>> lngLat, Size box, double padding) {
    if (lngLat.isEmpty) return const [];

    final midLat = lngLat.map((p) => p[1]).reduce((a, b) => a + b) / lngLat.length;
    final kx = math.cos(midLat * math.pi / 180).abs().clamp(0.05, 1.0);

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in lngLat) {
      final x = p[0] * kx, y = p[1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    final spanX = maxX - minX, spanY = maxY - minY;
    final innerW = math.max(1.0, box.width - padding * 2);
    final innerH = math.max(1.0, box.height - padding * 2);
    final scale = (spanX <= 0 && spanY <= 0)
        ? 1.0
        : math.min(
            spanX <= 0 ? double.infinity : innerW / spanX,
            spanY <= 0 ? double.infinity : innerH / spanY,
          );
    final drawnW = spanX * scale, drawnH = spanY * scale;
    final left = padding + (innerW - drawnW) / 2;
    final top = padding + (innerH - drawnH) / 2;

    return [
      for (final p in lngLat)
        Offset(
          left + (p[0] * kx - minX) * scale,
          // 위도는 위로 갈수록 크지만 화면의 y 는 아래로 갈수록 크다.
          top + (maxY - p[1]) * scale,
        ),
    ];
  }
}

/// 경로 한 장의 재료. 화면의 미리보기와 갤러리에 저장하는 사진이 **같은 painter** 를 쓴다 —
/// 둘이 다른 코드를 타면 보이는 것과 저장되는 것이 어긋난다.
class RouteArt {
  final List<List<double>> lngLat;
  final String distanceLabel;
  final String timeLabel;
  final String dateLabel;

  /// 산책 중에 한 탭으로 남긴 것들 (#340). 경로 위 **그 점**에 작은 표식을 찍는다.
  ///
  /// 좌표를 따로 안 받는다 — [WalkMoment.pathIndex] 가 [lngLat] 의 몇 번째인지를 가리키므로
  /// 좌표가 사는 자리가 늘지 않는다. 범위 밖 인덱스는 그냥 안 그린다(옛 초안·잘린 경로).
  final List<WalkMoment> moments;

  const RouteArt({
    required this.lngLat,
    required this.distanceLabel,
    required this.timeLabel,
    required this.dateLabel,
    this.moments = const [],
  });

  /// 점이 둘은 있어야 선이 된다.
  bool get drawable => lngLat.length >= 2;
}

/// 배경(단색 + 격자) · 경로(폴리라인) · 시작/끝 표시 · 아래쪽 글자(거리 · 시간 · 날짜).
class RouteCanvasPainter extends CustomPainter {
  final RouteArt art;
  final bool withCaption;

  const RouteCanvasPainter(this.art, {this.withCaption = true});

  static const _bgTop = T.surface;
  static const _bgBottom = Color(0xFFFFF1EA);
  static const _grid = Color(0x14463C64);
  static const _route = Color(0xFFFF7A59);
  static const _routeGlow = Color(0x33FF7A59);
  static const _start = Color(0xFF4CAF88);
  static const _end = T.textSecondary;
  static const _ink = T.textSecondary;

  /// 순간 표식의 색. 버튼 줄(`walk_moment_bar.dart`)과 **같은 색**이어야 한다 —
  /// 누를 때 본 색과 그림에 남는 색이 다르면 같은 일로 안 읽힌다.
  static const Map<WalkMomentKind, Color> _momentColors = {
    WalkMomentKind.poop: Color(0xFF9C6B4A),
    WalkMomentKind.pee: Color(0xFFD9A02B),
    WalkMomentKind.water: Color(0xFF3E9AD6),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgTop, _bgBottom],
        ).createShader(rect),
    );

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    final step = math.max(24.0, size.shortestSide / 10);
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final captionH = withCaption ? math.max(44.0, size.height * 0.16) : 0.0;
    final routeBox = Size(size.width, size.height - captionH);
    final padding = math.max(18.0, routeBox.shortestSide * 0.12);
    final points = RouteProjection.fit(art.lngLat, routeBox, padding);

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      final stroke = math.max(4.0, routeBox.shortestSide * 0.02);
      canvas.drawPath(
        path,
        Paint()
          ..color = _routeGlow
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke * 2.6,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _route
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke,
      );
      final dot = math.max(5.0, stroke * 1.4);
      canvas.drawCircle(points.first, dot + 2, Paint()..color = Colors.white);
      canvas.drawCircle(points.first, dot, Paint()..color = _start);
      canvas.drawCircle(points.last, dot + 2, Paint()..color = Colors.white);
      canvas.drawCircle(points.last, dot, Paint()..color = _end);
    } else if (points.length == 1) {
      canvas.drawCircle(points.first, 6, Paint()..color = _end);
    }

    _drawMoments(canvas, points, routeBox);

    if (withCaption) {
      final fontSize = math.max(11.0, captionH * 0.3);
      _text(canvas, '${art.distanceLabel}  ·  ${art.timeLabel}',
          Offset(padding * 0.8, size.height - captionH + captionH * 0.18),
          fontSize, FontWeight.w800, size.width - padding * 1.6);
      _text(canvas, art.dateLabel,
          Offset(padding * 0.8, size.height - captionH + captionH * 0.58),
          fontSize * 0.8, FontWeight.w600, size.width - padding * 1.6);
    }
  }

  void _text(Canvas canvas, String s, Offset at, double fontSize, FontWeight w, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: fontSize, fontWeight: w, color: _ink),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, at);
  }

  /// 경로 위의 표식. 선 위에 얹으므로 흰 테두리를 한 겹 두른다.
  void _drawMoments(Canvas canvas, List<Offset> points, Size routeBox) {
    if (points.isEmpty) return;
    final r = math.max(3.5, routeBox.shortestSide * 0.016);
    for (final moment in art.moments) {
      final i = moment.pathIndex;
      if (i == null || i < 0 || i >= points.length) continue;
      canvas.drawCircle(points[i], r + 1.6, Paint()..color = Colors.white);
      canvas.drawCircle(points[i], r, Paint()..color = _momentColors[moment.kind]!);
    }
  }

  @override
  bool shouldRepaint(RouteCanvasPainter old) =>
      old.art != art || old.withCaption != withCaption;
}

/// 갤러리에 넣을 PNG 한 장. 화면 트리 없이 `dart:ui` 로 바로 그린다 — 위젯이 없어도 되고,
/// 테스트에서도 그대로 돈다.
class RouteImage {
  static const Size defaultSize = Size(1080, 1350);

  static Future<Uint8List> renderPng(RouteArt art, {Size size = defaultSize}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    RouteCanvasPainter(art).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('경로 그림을 PNG 로 바꾸지 못했어요');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

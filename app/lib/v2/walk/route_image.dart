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
// ## 지도 바닥 (#483)
//
// 지도 키가 있는 빌드는 트래킹 화면이 끝내기 순간 지도 한 장을 찍어([MapGround], 네이버
// SDK 의 `takeSnapshot`) 바이트로 넘겨준다. 그러면 경로 상자 바닥이 그 지도이고, 점은 SDK 가
// 잰 화면 자리를 쓴다 — 여기서 투영하지 않는다(지도의 투영과 어긋난다). 스냅숏이 없으면(키
// 없는 빌드 · 못 찍음) 위의 단색 + 격자 그대로다. 타일 요청은 네이버가 자기 처리방침 아래
// 처리하는 것이고 우리 서버로 가는 것이 아니다 — `docs/00-product/legal-lbs-compliance.md` §1.4.
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

/// 끝내기 순간 트래킹 화면이 찍은 지도 한 장과, 그 위에서 경로 점들이 있는 자리 (#483).
///
/// 그림 파일들은 **바이트만** 받는다 — 파일 · 네트워크 · 지도 SDK 를 모른다(소스 잠금은
/// `route_photo_no_network_test` · `walk_share_no_network_test`). 지도 키 없는 빌드는 이것이
/// null 이라 예전 캔버스(단색 + 격자)로 그린다.
class MapGround {
  /// `takeSnapshot` 이 준 파일의 바이트. 형식(JPEG/PNG)은 디코더가 가린다.
  final Uint8List bytes;

  /// 스냅숏을 찍은 지도 위젯의 논리 픽셀 크기. 스냅숏 픽셀 = 논리 픽셀 × 배율이고, 배율은
  /// 그릴 때 이미지 크기에서 얻는다 — 기기마다 다른 값을 여기 적지 않는다.
  final Size viewSize;

  /// [RouteArt.lngLat] 과 **같은 길이**. 지도 위 논리 픽셀 자리(SDK 가 잰 것), 안 잰 점은 null.
  final List<Offset?> screenPoints;

  const MapGround({required this.bytes, required this.viewSize, required this.screenPoints});

  /// 점 [n] 개 중 SDK 에 자리를 물을 인덱스 — 처음 · 끝 · [keep](순간의 인덱스)은 반드시,
  /// 나머지는 [max] 개를 넘지 않게 고르게. 한 점에 한 번씩 플랫폼 채널을 건너므로 개수를 묶는다.
  static List<int> sampleIndices(int n, {Iterable<int?> keep = const [], int max = 120}) {
    if (n <= 0) return const [];
    final picked = <int>{0, n - 1};
    final stride = math.max(1, (n / math.max(1, max)).ceil());
    for (var i = 0; i < n; i += stride) {
      picked.add(i);
    }
    for (final k in keep) {
      if (k != null && k >= 0 && k < n) picked.add(k);
    }
    return picked.toList()..sort();
  }

  /// 오려낼 자리 — 점들의 경계 상자 [bbox] 에 여백을 두르고 [aspect](가로/세로)로 키운다.
  /// 이미지 **밖으로 나갈 수 있다** — 세로로 긴 경로를 가로로 넓은 상자에 넣을 때. 밖은
  /// [drawMapGround] 가 같은 지도를 흐리게 깔아 메운다(사진 앱의 레터박스).
  static Rect cropFor(Rect bbox, double aspect, {double margin = 0.18, double minMargin = 40}) {
    final m = math.max(margin * math.max(bbox.width, bbox.height), minMargin);
    final want = bbox.inflate(m);
    var w = want.width, h = want.height;
    if (w / h < aspect) {
      w = h * aspect;
    } else {
      h = w / aspect;
    }
    return Rect.fromCenter(center: want.center, width: w, height: h);
  }
}

/// 지도 바닥 위에서 경로가 놓일 자리 — 경로 사진 · 공유 카드 · 시트 미리보기가 같은 계산을 쓴다.
class MapPlacement {
  /// 이미지 픽셀 좌표의 오림 자리(이미지 밖으로 나갈 수 있다).
  final Rect crop;

  /// 캔버스 좌표의 점들 — [MapGround.screenPoints] 와 같은 길이. 안 잰 점과 범위 밖은 null.
  final List<Offset?> points;

  const MapPlacement(this.crop, this.points);

  /// [box] 에 그릴 자리. [from]..[to) 범위의 점만 센다(공유 카드는 양 끝을 자른다). 잰 점이
  /// 하나도 없으면 null — 그러면 부르는 쪽이 캔버스로 돌아간다.
  static MapPlacement? of(MapGround g, ui.Image image, Rect box, {int from = 0, int? to}) {
    if (g.viewSize.width <= 0 || g.viewSize.height <= 0 || box.isEmpty) return null;
    final sx = image.width / g.viewSize.width, sy = image.height / g.viewSize.height;
    final end = math.min(to ?? g.screenPoints.length, g.screenPoints.length);
    final px = List<Offset?>.filled(g.screenPoints.length, null);
    Rect? bbox;
    for (var i = math.max(0, from); i < end; i++) {
      final p = g.screenPoints[i];
      if (p == null) continue;
      final q = Offset(p.dx * sx, p.dy * sy);
      px[i] = q;
      final dot = Rect.fromPoints(q, q);
      bbox = bbox == null ? dot : bbox.expandToInclude(dot);
    }
    if (bbox == null) return null;
    final crop = MapGround.cropFor(bbox, box.width / box.height, minMargin: 40 * sx);
    final kx = box.width / crop.width, ky = box.height / crop.height;
    return MapPlacement(crop, [
      for (final q in px)
        q == null ? null : Offset(box.left + (q.dx - crop.left) * kx, box.top + (q.dy - crop.top) * ky),
    ]);
  }
}

/// 스냅숏 바이트 → 그림. `dart:ui` 만 쓴다 — 플러터 바인딩이 없는 순수 테스트에서도 돈다
/// (`decodeImageFromList` 는 `PaintingBinding` 을 요구한다). 못 읽는 바이트면 던진다.
Future<ui.Image> decodeMapBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// 흐린 바닥의 번짐 반지름. 층(layer)과 그 안의 그림을 이만큼 상자 밖까지 채워야 가장자리가
/// 투명과 섞여 바래지 않는다.
const double _blurSigma = 14;

/// 지도 바닥을 [box] 에 그린다 — 뒤에 같은 지도를 흐리게 깔고(오림이 이미지 밖으로 나가는 자리를
/// 메운다), 그 위에 오린 자리를 선명하게. 부르는 쪽이 모서리를 깎는다(clip).
void drawMapGround(Canvas canvas, ui.Image image, MapPlacement p, Rect box) {
  final full = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  canvas.save();
  canvas.clipRect(box);
  // 흐린 바닥: 이미지를 상자보다 번짐 반지름만큼 큰 자리에 cover 로 — 층의 가장자리 밖이
  // 투명이면 흐림이 그것을 끌어와 테두리가 바랜다.
  final wide = box.inflate(_blurSigma * 3);
  final scale = math.max(wide.width / image.width, wide.height / image.height);
  final w = image.width * scale, h = image.height * scale;
  final cover = Rect.fromLTWH(wide.left + (wide.width - w) / 2, wide.top + (wide.height - h) / 2, w, h);
  canvas.saveLayer(wide, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma));
  canvas.drawImageRect(image, full, cover, Paint()..filterQuality = FilterQuality.low);
  canvas.drawRect(wide, Paint()..color = const Color(0x2E000000));
  canvas.restore();
  // 선명한 오림: 이미지와 겹치는 부분만.
  final src = p.crop.intersect(full);
  if (src.width > 0 && src.height > 0) {
    final kx = box.width / p.crop.width, ky = box.height / p.crop.height;
    final dst = Rect.fromLTWH(
      box.left + (src.left - p.crop.left) * kx,
      box.top + (src.top - p.crop.top) * ky,
      src.width * kx,
      src.height * ky,
    );
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }
  canvas.restore();
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

  /// 끝내기 순간의 지도 스냅숏(#483). 없으면 단색 + 격자 캔버스.
  final MapGround? map;

  const RouteArt({
    required this.lngLat,
    required this.distanceLabel,
    required this.timeLabel,
    required this.dateLabel,
    this.moments = const [],
    this.map,
  });

  /// 점이 둘은 있어야 선이 된다.
  bool get drawable => lngLat.length >= 2;
}

/// 배경(단색 + 격자) · 경로(폴리라인) · 시작/끝 표시 · 아래쪽 글자(거리 · 시간 · 날짜).
class RouteCanvasPainter extends CustomPainter {
  final RouteArt art;
  final bool withCaption;

  /// 디코딩된 [RouteArt.map] — painter 는 동기라 여기서 디코딩할 수 없다. [RouteImage.renderPng]
  /// 와 끝내기 시트가 만든다. null 이면 캔버스.
  final ui.Image? map;

  const RouteCanvasPainter(this.art, {this.withCaption = true, this.map});

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
    // 지도 바닥(#483): 스냅숏이 있으면 경로 상자에 깔고 점은 SDK 가 잰 자리를 쓴다. 없으면
    // 위의 단색 + 격자 위에 기기 안에서 투영한 점이다. 둘 다 lngLat 과 같은 길이의 목록이라
    // 순간(moments)의 pathIndex 가 그대로 맞는다.
    final ground = map;
    final placement = ground == null || art.map == null
        ? null
        : MapPlacement.of(art.map!, ground, Offset.zero & routeBox);
    final List<Offset?> slots;
    if (placement != null) {
      drawMapGround(canvas, ground!, placement, Offset.zero & routeBox);
      slots = placement.points;
    } else {
      slots = RouteProjection.fit(art.lngLat, routeBox, padding);
    }
    final points = slots.whereType<Offset>().toList();

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

    _drawMoments(canvas, slots, routeBox);

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
  void _drawMoments(Canvas canvas, List<Offset?> points, Size routeBox) {
    if (points.isEmpty) return;
    final r = math.max(3.5, routeBox.shortestSide * 0.016);
    for (final moment in art.moments) {
      final i = moment.pathIndex;
      if (i == null || i < 0 || i >= points.length) continue;
      final at = points[i];
      if (at == null) continue;
      canvas.drawCircle(at, r + 1.6, Paint()..color = Colors.white);
      canvas.drawCircle(at, r, Paint()..color = _momentColors[moment.kind]!);
    }
  }

  @override
  bool shouldRepaint(RouteCanvasPainter old) =>
      old.art != art || old.withCaption != withCaption || old.map != map;
}

/// 갤러리에 넣을 PNG 한 장. 화면 트리 없이 `dart:ui` 로 바로 그린다 — 위젯이 없어도 되고,
/// 테스트에서도 그대로 돈다.
class RouteImage {
  /// 내보내는 그림의 크기 — **정사각**이다(#517 · 사장님 결정 A).
  ///
  /// ## 4:5 였을 때 무엇이 잘렸나
  ///
  /// 커뮤니티 카드는 **정사각까지만** 그린다(#465 — 세로 사진 하나가 화면 절반을 먹으면 한
  /// 화면에 글이 하나뿐이다. Reddit 의 카드와 같은 판단). 그 카드에 4:5 그림을 가운데 맞춰
  /// 넣으면 위아래가 잘리고, 이 그림은 **아래 16% 가 캡션**이라 `0.90km · 01:13` 이 먼저
  /// 잘렸다. 홈의 "이웃의 사진" 줄(96×96 정사각 썸네일)에서도 같았다.
  ///
  /// ## 왜 그림을 바꾸고 카드를 안 바꿨나
  ///
  /// 둘 다 근거가 적힌 결정이었다. 그런데 **이 그림은 우리가 만드는 것**이고 캡션이 그
  /// 그림의 요점이다 — 자를 수 없는 것을 자를 수 있는 자리에 두지 않는 편이 낫다. 인스타그램
  /// (1:1 이 원래 기본 비율) · 카카오톡도 정사각을 그대로 그린다. 카드의 "정사각까지" 도,
  /// 피드의 4:5 상한도 그대로 둔다.
  ///
  /// 공유 카드([WalkShareImage.defaultSize])는 **4:5 그대로**다. 그쪽은 우리 피드에 안
  /// 들어가고 인스타 피드에서 세로가 길수록 크게 보인다 — 자르는 자리가 없으면 4:5 가 낫다.
  static const Size defaultSize = Size(1080, 1080);

  static Future<Uint8List> renderPng(RouteArt art, {Size size = defaultSize}) async {
    // 지도 바닥은 여기서 디코딩한다 — painter 는 동기다. 못 읽는 바이트면 캔버스로 그린다.
    ui.Image? map;
    final ground = art.map;
    if (ground != null) {
      try {
        map = await decodeMapBytes(ground.bytes);
      } catch (_) {
        map = null;
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    RouteCanvasPainter(art, map: map).paint(canvas, size);
    map?.dispose();
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

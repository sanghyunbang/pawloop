// lib/v2/walk/walk_share_card.dart
//
// 산책 한 번을 **한 장**으로 — 이슈 #344.
//
// ## 왜 있나
//
// 사용자가 앱 밖으로 가져갈 것이 없었다. 종료 시트의 "경로 사진 저장" 은 선 하나를 갤러리에
// 남길 뿐이라 거리도 시간도 우리 아이 이름도 없다. 반려인은 산책 사진을 인스타·카톡 가족방에
// 올린다 — 거기 붙는 카드 한 장이 **비용 0 의 유입 경로**다.
//
// ## 지도 타일이 없다 · 양 끝을 자른다
//
// 배경은 `route_image.dart` 와 같은 단색+격자다(#310 — 네이버 지도 위에 그리면 카메라 궤적이
// 곧 경로라 좌표가 나간다). 그리고 **양 끝 100m 를 버린다**(#339 의 `trimCourseEnds` 와 같은
// 규칙) — 카드는 남에게 보내는 것이고, 시작점은 대개 집 앞이다.
//
// 자르고 남는 것이 없으면(아주 짧은 산책) **선을 안 그린다.** 짧으니까 그냥 그리자는 유혹이
// 정확히 집 앞을 그리는 길이다.
//
// ## 서버가 준 기록에는 선이 없다
//
// A안(#235)에서 경로는 서버로 안 올라간다. 그래서 **종료 시트**(메모리에 좌표가 있다)는 선이
// 있는 카드를, **기록 목록**(서버에서 받은 것)은 숫자만 있는 카드를 만든다. 둘이 같은 코드를
// 지나므로 "어느 쪽은 되고 어느 쪽은 안 된다" 가 생기지 않는다.
//
// ## 네트워크가 없다
//
// 이 파일도 `walk_share.dart` 도 `AuthedClient`·`package:http` 를 import 하지 않는다.
// `walk_share_no_network_test.dart` 가 소스로 잠근다.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/course_path.dart';
import 'route_image.dart';

/// 카드 한 장의 재료.
///
/// [lngLat] 은 **자르기 전** 좌표를 그대로 준다 — 자르는 것은 [trimmedPath] 한 곳이다.
/// 호출부가 자르면 "자른 곳" 이 둘이 되고 그중 하나가 언젠가 안 자른다.
class WalkShareCard {
  final String dogName;

  /// 아이 아바타의 테두리색. 프로필에서 고른 그 색이다 — 카드의 강조색으로 쓴다.
  final Color accent;

  final String dateLabel;
  final String distanceLabel;
  final String timeLabel;
  final String paceLabel;

  /// 사용자가 장소를 붙였을 때만 (#338). 없으면 카드에 자리 자체가 없다.
  final String? placeName;

  /// 걸은 좌표 `[경도, 위도]`. 서버에서 받은 기록에는 없다(A안 #235).
  final List<List<double>>? lngLat;

  const WalkShareCard({
    required this.dogName,
    required this.accent,
    required this.dateLabel,
    required this.distanceLabel,
    required this.timeLabel,
    required this.paceLabel,
    this.placeName,
    this.lngLat,
  });

  /// 남에게 보낼 수 있는 선. 양 끝 100m 를 버리고, 남는 것이 없으면 `null`.
  List<List<double>>? get trimmedPath => trimCourseEnds(lngLat);

  /// 선을 그릴 수 있는가. 아니면 숫자만 있는 카드다.
  bool get hasRoute => (trimmedPath?.length ?? 0) >= 2;
}

/// 함께 나간 아이들을 카드 첫 줄에 쓸 한 문장으로 (#343).
///
/// 한 마리면 이름 그대로, 둘이면 `보리 · 초코`, 셋 이상이면 `보리 외 2마리` 다.
/// **셋부터 줄이는 이유**: 카드 첫 줄은 62pt 라 이름 셋이 들어가면 말줄임으로 잘린다.
/// 잘린 이름은 안 적느니만 못하다.
String joinDogNames(List<String> names) {
  final kept = names.where((n) => n.trim().isNotEmpty).map((n) => n.trim()).toList();
  if (kept.isEmpty) return '';
  if (kept.length == 1) return kept.first;
  if (kept.length == 2) return '${kept[0]} · ${kept[1]}';
  return '${kept.first} 외 ${kept.length - 1}마리';
}

/// 받침이 있으면 `과`, 없으면 `와`.
///
/// 이것이 없으면 "구름와 2.1km 걸었어요" 가 나간다 — 남에게 보내는 글이라 조사 하나가
/// 그대로 흠이 된다. 한글이 아닌 이름(영문·숫자)은 `와` 로 둔다: 한국어 화자가 읽을 때
/// 대개 그렇게 읽고, 어느 쪽이든 틀린 규칙이 없다.
String withParticle(String name) {
  if (name.isEmpty) return '와';
  final last = name.codeUnitAt(name.length - 1);
  if (last < 0xAC00 || last > 0xD7A3) return '와';
  // 한글 음절 = 초성×588 + 중성×28 + 종성. 나머지가 0 이면 받침이 없다.
  return (last - 0xAC00) % 28 == 0 ? '와' : '과';
}

/// 1080×1350 한 장. 화면 트리 없이 `dart:ui` 로 그린다 — 테스트에서도 그대로 돈다.
class WalkShareCardPainter extends CustomPainter {
  final WalkShareCard card;

  const WalkShareCardPainter(this.card);

  static const _bgTop = Color(0xFFF6F1FF);
  static const _bgBottom = Color(0xFFFFF1EA);
  static const _grid = Color(0x14463C64);
  static const _ink = Color(0xFF463C64);
  static const _inkSoft = Color(0x99463C64);
  static const _routeGlow = Color(0x33FF7A59);
  static const _start = Color(0xFF4CAF88);

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
      ..strokeWidth = size.shortestSide / 540;
    final step = size.shortestSide / 10;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pad = size.width * 0.09;
    final unit = size.width / 1080;

    // ── 머리: 아이 이름 · 날짜 ────────────────────────────
    _text(canvas, card.dogName, Offset(pad, size.height * 0.075),
        62 * unit, FontWeight.w800, size.width - pad * 2, _ink);
    _text(canvas, card.dateLabel, Offset(pad, size.height * 0.075 + 78 * unit),
        30 * unit, FontWeight.w600, size.width - pad * 2, _inkSoft);

    // 아이 색 한 줄 — 아바타 테두리와 같은 색이라 "누구의 산책인지" 가 색으로도 남는다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, size.height * 0.075 - 26 * unit, 96 * unit, 10 * unit),
        Radius.circular(5 * unit),
      ),
      Paint()..color = card.accent,
    );

    // ── 가운데: 경로 ──────────────────────────────────────
    final routeTop = size.height * 0.20;
    final routeBottom = size.height * 0.70;
    final routeBox = Rect.fromLTRB(pad * 0.6, routeTop, size.width - pad * 0.6, routeBottom);
    if (card.hasRoute) {
      _drawRoute(canvas, routeBox, unit);
    } else {
      _text(
        canvas,
        '경로는 이 기기에만 있어요',
        Offset(pad, routeTop + (routeBottom - routeTop) / 2 - 20 * unit),
        30 * unit,
        FontWeight.w600,
        size.width - pad * 2,
        _inkSoft,
        center: true,
      );
    }

    // ── 아래: 숫자 셋 ─────────────────────────────────────
    final statsY = size.height * 0.76;
    final colW = (size.width - pad * 2) / 3;
    const labels = ['거리', '시간', '페이스'];
    final values = [card.distanceLabel, card.timeLabel, card.paceLabel];
    for (var i = 0; i < 3; i++) {
      final x = pad + colW * i;
      _text(canvas, values[i], Offset(x, statsY), 54 * unit, FontWeight.w800, colW, _ink);
      _text(canvas, labels[i], Offset(x, statsY + 68 * unit), 28 * unit,
          FontWeight.w600, colW, _inkSoft);
    }

    // ── 꼬리: 장소 · 마크 ─────────────────────────────────
    final footY = size.height - pad * 0.9;
    final place = card.placeName;
    if (place != null && place.isNotEmpty) {
      _text(canvas, '📍 $place', Offset(pad, footY - 46 * unit), 28 * unit,
          FontWeight.w600, size.width - pad * 2 - 200 * unit, _inkSoft);
    }
    _text(canvas, 'Pawloop', Offset(size.width - pad - 200 * unit, footY - 46 * unit),
        30 * unit, FontWeight.w800, 200 * unit, card.accent, alignRight: true);
  }

  void _drawRoute(Canvas canvas, Rect box, double unit) {
    final points = RouteProjection.fit(card.trimmedPath!, box.size, 24 * unit)
        .map((o) => o.translate(box.left, box.top))
        .toList();
    if (points.length < 2) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final stroke = math.max(6.0, box.shortestSide * 0.022);
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
        ..color = card.accent
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke,
    );
    final dot = stroke * 1.3;
    canvas.drawCircle(points.first, dot + 3 * unit, Paint()..color = Colors.white);
    canvas.drawCircle(points.first, dot, Paint()..color = _start);
    canvas.drawCircle(points.last, dot + 3 * unit, Paint()..color = Colors.white);
    canvas.drawCircle(points.last, dot, Paint()..color = _ink);
  }

  void _text(Canvas canvas, String s, Offset at, double fontSize, FontWeight weight,
      double maxW, Color color,
      {bool center = false, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: center
          ? TextAlign.center
          : alignRight
              ? TextAlign.right
              : TextAlign.left,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, center ? Offset(at.dx + (maxW - tp.width) / 2, at.dy) : at);
  }

  @override
  bool shouldRepaint(WalkShareCardPainter old) => old.card != card;
}

/// 카드 PNG 한 장.
class WalkShareImage {
  static const Size defaultSize = Size(1080, 1350);

  static Future<Uint8List> renderPng(WalkShareCard card, {Size size = defaultSize}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    WalkShareCardPainter(card).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('공유 카드를 PNG 로 바꾸지 못했어요');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

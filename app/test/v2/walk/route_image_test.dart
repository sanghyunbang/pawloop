// 경로를 타일 없이 그린다 — 이슈 #310. 투영이 상자 안에 들어오는가, PNG 가 실제로 나오는가.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;
import 'package:heat_trip_flutter/v2/walk/route_image.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';

// 서울숲 근처 — [경도, 위도] (계약·초안 큐와 같은 순서).
const _seoul = [
  [127.0374, 37.5445],
  [127.0402, 37.5455],
  [127.0420, 37.5430],
  [127.0390, 37.5420],
];

ui.Image _solid(int w, int h, Color color) {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
  return rec.endRecording().toImageSync(w, h);
}

Future<Uint8List> _solidPng(int w, int h, Color color) async {
  final img = _solid(w, h, color);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// PNG 의 픽셀을 읽는다 — 형식이 아니라 **값**을 재려고.
class _Pixels {
  final int width;
  final Uint8List rgba;
  _Pixels(this.width, this.rgba);
  int _at(int x, int y, int ch) => rgba[(y * width + x) * 4 + ch];
  int green(int x, int y) => _at(x, y, 1);
  int blue(int x, int y) => _at(x, y, 2);
}

Future<_Pixels> _pixels(Uint8List png) async {
  final img = await decodeImageFromList(png);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = _Pixels(img.width, data!.buffer.asUint8List());
  img.dispose();
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteProjection.fit', () {
    test('모든 점이 여백 안에 들어오고, 경계 상자의 끝이 여백선에 닿는다', () {
      const box = Size(400, 300);
      const pad = 40.0;
      final pts = RouteProjection.fit(_seoul, box, pad);

      expect(pts, hasLength(_seoul.length));
      for (final p in pts) {
        expect(p.dx, inInclusiveRange(pad - 0.001, box.width - pad + 0.001));
        expect(p.dy, inInclusiveRange(pad - 0.001, box.height - pad + 0.001));
      }
      final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
      final touchesX = (xs.reduce((a, b) => a < b ? a : b) - pad).abs() < 0.001 &&
          (xs.reduce((a, b) => a > b ? a : b) - (box.width - pad)).abs() < 0.001;
      final touchesY = (ys.reduce((a, b) => a < b ? a : b) - pad).abs() < 0.001 &&
          (ys.reduce((a, b) => a > b ? a : b) - (box.height - pad)).abs() < 0.001;
      expect(touchesX || touchesY, isTrue,
          reason: '등방 확대라 긴 축이 여백선에 닿고 짧은 축은 가운데 정렬된다');
    });

    test('북쪽이 위다 — 위도가 큰 점이 화면에서 더 위(작은 y)에 놓인다', () {
      final pts = RouteProjection.fit(_seoul, const Size(400, 300), 20);
      // _seoul[1] 이 가장 북쪽(37.5455), _seoul[3] 이 가장 남쪽(37.5420)
      expect(pts[1].dy, lessThan(pts[3].dy));
    });

    test('점이 하나면 상자 가운데다 — 나눗셈이 0 이 되는 자리에서 죽지 않는다', () {
      final pts = RouteProjection.fit([_seoul.first], const Size(200, 100), 10);
      expect(pts.single.dx, closeTo(100, 0.001));
      expect(pts.single.dy, closeTo(50, 0.001));
    });

    test('빈 경로는 빈 목록이다', () {
      expect(RouteProjection.fit(const [], const Size(200, 100), 10), isEmpty);
    });
  });

  group('RouteImage.renderPng', () {
    RouteArt art() => const RouteArt(
          lngLat: _seoul,
          distanceLabel: '1.24km',
          timeLabel: '18:40',
          dateLabel: '2026.09.06 14:20 출발',
        );

    test('PNG 가 나오고 크기가 요청한 대로다', () async {
      final png = await RouteImage.renderPng(art(), size: const Size(300, 400));

      expect(png.length, greaterThan(100));
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: 'PNG 서명 — 갤러리가 이걸로 형식을 안다');
      // IHDR: 너비·높이가 16~23 바이트에 big-endian 으로 있다
      final data = ByteData.sublistView(png);
      expect(data.getUint32(16), 300);
      expect(data.getUint32(20), 400);
    });

    test('내보내는 크기는 정사각이다 — 카드가 정사각까지만 그리기 때문이다 (#517)', () async {
      final size = RouteImage.defaultSize;

      expect(size.width, size.height,
          reason: '커뮤니티 카드는 정사각까지만 그린다(#465). 4:5 를 넣으면 가운데를 맞추며 '
              '위아래를 자르고, 이 그림은 아래 16% 가 캡션이라 "0.90km · 01:13" 이 먼저 잘린다. '
              '홈의 "이웃의 사진" 96×96 썸네일도 같다.');
      expect(size.width, greaterThanOrEqualTo(1080),
          reason: '폰 화면 폭보다 작으면 피드에서 흐리게 보인다');
    });

    test('공유 카드는 4:5 그대로다 — 우리 피드에 안 들어간다', () {
      expect(WalkShareImage.defaultSize.width / WalkShareImage.defaultSize.height,
          closeTo(0.8, 0.001),
          reason: '인스타 피드에서는 세로가 길수록 크게 보이고, 그쪽엔 자르는 카드가 없다. '
              '경로 사진을 정사각으로 바꿨다고 이것까지 따라가면 안 된다');
    });

    test('정사각으로 그려도 캡션 글자가 그림 안에 남는다', () async {
      final pixels = await _pixels(
          await RouteImage.renderPng(art(), size: const Size(240, 240)));

      // 캡션 띠(아래 16%)에 배경보다 어두운 픽셀이 있는가 — 글자가 거기 그려졌다는 뜻이다.
      var inked = 0;
      for (var y = 207; y < 240; y++) {
        for (var x = 0; x < 240; x++) {
          if (pixels.green(x, y) < 180) inked++;
        }
      }
      expect(inked, greaterThan(20),
          reason: '캡션 띠가 비었다면 글자가 그림 밖으로 나간 것이다 — 자르기 전에 이미 없다');
    });

    test('점이 하나뿐이어도 그림은 나온다 — 시트는 그리지 않지만 렌더러가 죽으면 안 된다', () async {
      final png = await RouteImage.renderPng(
        const RouteArt(lngLat: [[127.0374, 37.5445]], distanceLabel: '0.00km', timeLabel: '00:05', dateLabel: ''),
        size: const Size(120, 120),
      );
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('drawable 은 점이 둘부터다', () {
      expect(art().drawable, isTrue);
      expect(const RouteArt(lngLat: [[1, 1]], distanceLabel: '', timeLabel: '', dateLabel: '').drawable, isFalse);
    });
  });

  // ── 지도 바닥 (#483) ─────────────────────────────────────────
  //
  // 트래킹 화면이 찍은 스냅숏은 **바이트와 SDK 가 잰 점 자리** 로 온다. 여기서는 그 재료로
  // 오림 자리와 점의 변환을 값으로 재고, 실제 PNG 의 픽셀을 읽어 바닥이 바뀌는 것을 본다.
  group('MapGround (#483)', () {
    test('sampleIndices — 처음 · 끝 · 순간 인덱스는 반드시, 나머지는 max 개 안팎으로 고르게', () {
      // 1001 개 — 보폭 9 로는 999 까지만 닿는다. 마지막 점 1000 은 "반드시" 규칙이 넣어야 든다.
      final picked = MapGround.sampleIndices(1001, keep: const [7, null, 513, -1, 5000], max: 120);

      expect(picked.first, 0);
      expect(picked.last, 1000);
      expect(picked, containsAll([7, 513]));
      expect(picked, isNot(contains(-1)));
      expect(picked, isNot(contains(5000)));
      expect(picked.length, lessThanOrEqualTo(120 + 4), reason: '한 점에 채널 한 번 — 개수를 묶는다');
      expect(picked, orderedEquals(picked.toSet().toList()..sort()), reason: '중복 없이 오름차순');
    });

    test('sampleIndices — 점이 적으면 전부다', () {
      expect(MapGround.sampleIndices(5), [0, 1, 2, 3, 4]);
      expect(MapGround.sampleIndices(0), isEmpty);
    });

    test('cropFor — 경계 상자 + 여백을 품고 비율을 맞춘다. 이미지 밖으로 나가도 된다(레터박스)', () {
      final bbox = const Rect.fromLTWH(100, 100, 200, 400);

      final crop = MapGround.cropFor(bbox, 2.0);

      // 여백 = max(0.18 × 400, 40) = 72 → 344 × 544, 비율 2 → 폭이 1088 로 자란다
      expect(crop.width / crop.height, closeTo(2.0, 1e-9));
      expect(crop.height, closeTo(544, 1e-9));
      expect(crop.width, closeTo(1088, 1e-9));
      expect(crop.center, bbox.center);
      expect(crop.left, lessThan(0), reason: '세로로 긴 경로를 넓은 상자에 — 이미지 밖으로 나간다');
      expect(crop.contains(bbox.topLeft) && crop.contains(bbox.bottomRight), isTrue);
    });

    test('MapPlacement.of — 논리 픽셀 × 배율 → 오림 → 상자 좌표. 안 잰 점은 null 로 남는다', () async {
      final image = _solid(200, 400, const Color(0xFF00C853));
      final g = MapGround(
        bytes: Uint8List(0),
        viewSize: const Size(100, 200), // 배율 2
        screenPoints: const [Offset(10, 20), null, Offset(60, 120)],
      );

      final p = MapPlacement.of(g, image, const Rect.fromLTWH(0, 0, 100, 100))!;

      // 픽셀 (20,40)·(120,240) → 경계 100×200, 여백 max(36, 40×2)=80 → 260×360 → 비율 1 → 360×360,
      // 가운데 (70,140) → 오림 (-110,-40)-(250,320). 상자 100 이라 배율 100/360.
      expect(p.crop.left, closeTo(-110, 1e-6));
      expect(p.crop.top, closeTo(-40, 1e-6));
      expect(p.crop.width, closeTo(360, 1e-6));
      expect(p.points.length, 3);
      expect(p.points[0]!.dx, closeTo((20 + 110) * 100 / 360, 1e-6));
      expect(p.points[0]!.dy, closeTo((40 + 40) * 100 / 360, 1e-6));
      expect(p.points[1], isNull);
      expect(p.points[2]!.dx, closeTo((120 + 110) * 100 / 360, 1e-6));
      expect(p.points[2]!.dy, closeTo((240 + 40) * 100 / 360, 1e-6));
      image.dispose();
    });

    test('MapPlacement.of — 범위 밖 점은 세지 않는다(공유 카드의 잘라낸 구간) · 잰 점이 없으면 null', () {
      final image = _solid(100, 100, const Color(0xFF00C853));
      final g = MapGround(
        bytes: Uint8List(0),
        viewSize: const Size(100, 100),
        screenPoints: const [Offset(0, 0), Offset(50, 50), Offset(99, 99)],
      );

      final mid = MapPlacement.of(g, image, const Rect.fromLTWH(0, 0, 50, 50), from: 1, to: 2)!;
      expect(mid.points[0], isNull);
      expect(mid.points[2], isNull);
      expect(mid.points[1], isNotNull);
      expect(mid.crop.center, const Offset(50, 50), reason: '오림은 남은 점의 가운데다 — 집 앞이 가운데에 오지 않는다');

      expect(MapPlacement.of(g, image, const Rect.fromLTWH(0, 0, 50, 50), from: 3), isNull);
      final none = MapGround(bytes: Uint8List(0), viewSize: const Size(100, 100), screenPoints: const [null, null]);
      expect(MapPlacement.of(none, image, const Rect.fromLTWH(0, 0, 50, 50)), isNull);
      image.dispose();
    });

    test('스냅숏이 있으면 경로 상자의 바닥이 지도다 — 아래 글자 띠는 그대로 캔버스', () async {
      final png = await _solidPng(60, 120, const Color(0xFF00C853));
      final art = RouteArt(
        lngLat: _seoul,
        distanceLabel: '1.24km',
        timeLabel: '18:40',
        dateLabel: '2026.09.06',
        map: MapGround(
          bytes: png,
          viewSize: const Size(60, 120),
          screenPoints: [for (var i = 0; i < _seoul.length; i++) Offset(20 + i * 5.0, 30 + i * 10.0)],
        ),
      );

      final withMap = await _pixels(await RouteImage.renderPng(art, size: const Size(200, 250)));
      final plain = await _pixels(await RouteImage.renderPng(
          RouteArt(lngLat: _seoul, distanceLabel: '1.24km', timeLabel: '18:40', dateLabel: '2026.09.06'),
          size: const Size(200, 250)));

      // 경로 상자(위 210px)의 구석 — 선이 안 지나는 자리
      expect(withMap.green(4, 4), greaterThan(150), reason: '지도(초록)가 바닥이다');
      expect(withMap.blue(4, 4), lessThan(120));
      expect(plain.blue(4, 4), greaterThan(200), reason: '스냅숏이 없으면 크림색 캔버스');
      // 글자 띠(아래 40px)는 둘 다 캔버스
      expect(withMap.blue(4, 246), greaterThan(200));
      expect(plain.blue(4, 246), greaterThan(200));
    });

    test('바이트를 못 읽으면 캔버스로 그린다 — 죽지 않는다', () async {
      final art = RouteArt(
        lngLat: _seoul,
        distanceLabel: '1.24km',
        timeLabel: '18:40',
        dateLabel: '2026.09.06',
        map: MapGround(bytes: Uint8List.fromList([1, 2, 3]), viewSize: const Size(60, 120), screenPoints: const []),
      );

      final px = await _pixels(await RouteImage.renderPng(art, size: const Size(200, 250)));

      expect(px.blue(4, 4), greaterThan(200));
    });
  });
}

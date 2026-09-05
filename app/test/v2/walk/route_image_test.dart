// 경로를 타일 없이 그린다 — 이슈 #310. 투영이 상자 안에 들어오는가, PNG 가 실제로 나오는가.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/walk/route_image.dart';

// 서울숲 근처 — [경도, 위도] (계약·초안 큐와 같은 순서).
const _seoul = [
  [127.0374, 37.5445],
  [127.0402, 37.5455],
  [127.0420, 37.5430],
  [127.0390, 37.5420],
];

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
}

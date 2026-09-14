// 공유 카드의 사진 배경 — 이슈 #450. 사진이 있으면 카드 바닥이 사진이고, 없으면 예전 그대로다.
//
// 픽셀 하나를 찍지 않는다 — 선·글자가 지나갈 수 있다. 가운데 띠(세로 35~55% · 가로 20~80%)의
// 평균 색으로 본다: 사진(빨강)이 깔리면 빨강이 초록보다 훨씬 크고, 없으면 밝은 단색이다.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';

Uint8List _redPhoto() {
  final photo = img.Image(width: 8, height: 10);
  img.fill(photo, color: img.ColorRgb8(220, 20, 20));
  return Uint8List.fromList(img.encodePng(photo));
}

WalkShareCard _card({Uint8List? photo}) => WalkShareCard(
      dogName: '보리',
      accent: const Color(0xFFFF8F63),
      dateLabel: '2026.09.14 07:00 출발',
      distanceLabel: '1.2km',
      timeLabel: '00:24',
      paceLabel: "20'00\"",
      lngLat: const [[127.0374, 37.5445], [127.0402, 37.5455]],
      photo: photo,
    );

({double r, double g, double b}) _middleBand(Uint8List png) {
  final decoded = img.decodePng(png)!;
  double r = 0, g = 0, b = 0;
  var n = 0;
  for (var y = (decoded.height * 0.35).round(); y < (decoded.height * 0.55).round(); y++) {
    for (var x = (decoded.width * 0.2).round(); x < (decoded.width * 0.8).round(); x++) {
      final p = decoded.getPixel(x, y);
      r += p.r; g += p.g; b += p.b; n++;
    }
  }
  return (r: r / n, g: g / n, b: b / n);
}

void main() {
  // 사진 디코딩은 바인딩이 있어야 한다 — 실제 앱은 늘 있고, 순수 테스트엔 없다.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('사진이 있으면 카드 가운데 띠가 사진(빨강)이다 — 위아래만 스크림', () async {
    final png = await WalkShareImage.renderPng(_card(photo: _redPhoto()), size: const Size(216, 270));

    final band = _middleBand(png);
    expect(band.r - band.g, greaterThan(80), reason: '사진의 빨강이 바닥에 깔린다 (r=${band.r}, g=${band.g})');
    expect(band.r - band.b, greaterThan(80));
  });

  test('사진이 없으면 예전 바닥(밝은 단색)이다 — 빨강이 아니다', () async {
    final png = await WalkShareImage.renderPng(_card(), size: const Size(216, 270));

    final band = _middleBand(png);
    expect(band.r - band.g, lessThan(40), reason: '바닥이 빨갛지 않다 (r=${band.r}, g=${band.g})');
    expect((band.r + band.g + band.b) / 3, greaterThan(170), reason: '밝은 바닥');
  });

  test('못 읽는 바이트면 사진 없이 그린다 — 카드가 죽지 않는다', () async {
    final png = await WalkShareImage.renderPng(
        _card(photo: Uint8List.fromList([1, 2, 3])), size: const Size(216, 270));

    final band = _middleBand(png);
    expect(band.r - band.g, lessThan(40));
  });

  test('hasPhoto 는 바이트가 있을 때만', () {
    expect(_card().hasPhoto, isFalse);
    expect(_card(photo: Uint8List(0)).hasPhoto, isFalse);
    expect(_card(photo: _redPhoto()).hasPhoto, isTrue);
  });
}

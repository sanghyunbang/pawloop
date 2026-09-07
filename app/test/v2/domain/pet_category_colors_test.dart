// 지도 카테고리 아홉의 색이 서로 구분되는가 (#328).
//
// 걸어 봤을 때 여행지·레포츠·산책로가 모두 초록, 쇼핑·펫샵이 모두 보라였다 — 범례가
// 있어도 핀을 구분할 수 없었다. 색 사이의 RGB 거리를 잠근다. 새 카테고리를 더할 때
// 이웃 색과 겹치면 여기서 빨강이다.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/pet.dart';

double _distance(int a, int b) {
  final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
  final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
  return sqrt(pow(ar - br, 2) + pow(ag - bg, 2) + pow(ab - bb, 2).toDouble());
}

void main() {
  test('아홉 색이 어느 둘도 가깝지 않다 — RGB 거리 80 이상', () {
    const minDistance = 80.0;
    for (var i = 0; i < kPetCategories.length; i++) {
      for (var j = i + 1; j < kPetCategories.length; j++) {
        final a = kPetCategories[i], b = kPetCategories[j];
        final d = _distance(a.color.toARGB32() & 0xFFFFFF, b.color.toARGB32() & 0xFFFFFF);
        expect(d, greaterThanOrEqualTo(minDistance),
            reason: '${a.label}(${a.color}) 와 ${b.label}(${b.color}) 가 너무 비슷하다: ${d.toStringAsFixed(0)}');
      }
    }
  });

  test('아홉 아이콘도 전부 다르다 — 색약인 사람은 아이콘으로 가른다', () {
    final icons = kPetCategories.map((c) => c.icon).toSet();
    expect(icons, hasLength(kPetCategories.length));
  });
}

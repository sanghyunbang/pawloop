// 디자인 토큰 — 이슈 #447.
//
// 사장님 결정(2026-09-14): "배경은 시각적 부담 없는 흰색으로, 색은 버튼이든 외곽선에." 그 전의
// 라일락 바탕·핑크 CTA 는 핑크 위주라 부담스럽다고 했다. 이 파일은 그 결정을 **값으로** 잠근다.
//
// ## 소스를 읽는 검사가 하나 있다
//
// 브랜드 색을 화면에 인라인 `Color(0x…)` 로 적던 351곳을 토큰으로 모았다(#455). 누가 다시
// `0xFFD89BFF` 를 화면에 적으면 토큰 값을 바꿔도 그 자리는 옛 색으로 남는다 — 그래서 `lib/` 를
// 읽어 옛 핑크·라일락 리터럴이 없는지 본다. 위젯을 띄우지 않고 파일을 읽는 검사라 빠르다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/theme/app_tokens.dart';
import 'package:heat_trip_flutter/v2/theme/themes.dart';

/// 2026-09-13 까지의 브랜드 색. 어느 화면에도 다시 나타나면 안 된다.
const _retired = {
  '0xFFD89BFF': '라일락(예전 SIG 끝)',
  '0xFFFF7E8A': '코랄핑크(예전 CTA 끝)',
  '0xFF8E7BFF': '라일락 강조색',
  '0xFF9B7BFF': '보라',
  '0xFFF3E8F9': '라일락 바탕 위',
  '0xFFE4D6F0': '라일락 바탕 아래',
  '0xFFD4B0FF': '라일락 블롭',
};

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('바탕은 흰색이고 기본 테마도 흰색이다 — 블롭이 없다', () {
    expect(T.bgTop, Colors.white);
    expect(T.bgBottom, Colors.white);
    final base = kThemes[0];
    expect(base.name, '화이트');
    expect(base.baseTop, Colors.white);
    expect(base.baseBottom, Colors.white);
    expect([base.blob1, base.blob2, base.blob3], everyElement(Colors.white),
        reason: '기본 테마에 색 블롭이 있으면 흰 바탕이 아니다');
  });

  test('흰 바탕이라 카드는 외곽선이 만든다 — 테두리가 보이는 색이고 배경은 흰색', () {
    expect(T.cardBg, Colors.white);
    expect(T.cardBorder.a, 1.0, reason: '반투명 흰 테두리는 흰 바탕에서 안 보인다');
    expect(_contrast(T.cardBorder, Colors.white), greaterThan(1.1));
    expect(T.line.a, 1.0);
  });

  test('강조색 하나에 흰 글자가 읽힌다 — 4:1 이상, 채움 버튼 중간색은 3:1 이상', () {
    expect(_contrast(T.accent, Colors.white), greaterThanOrEqualTo(4.0));
    final mid = Color.lerp(T.warm.colors.first, T.warm.colors.last, 0.5)!;
    expect(_contrast(mid, Colors.white), greaterThanOrEqualTo(3.0),
        reason: '채움 버튼의 흰 글자는 그라데이션 중간색 위에 놓인다');
    expect(_contrast(T.textPrimary, Colors.white), greaterThanOrEqualTo(12.0));
    expect(_contrast(T.textSecondary, Colors.white), greaterThanOrEqualTo(7.0));
  });

  test('그라데이션에 핑크·라일락이 없다', () {
    for (final c in [...T.sig.colors, ...T.warm.colors, T.accent]) {
      // 핑크·보라는 파랑 성분이 빨강에 가깝거나 크다. 코랄·살구는 파랑이 빨강의 절반 아래다.
      expect(c.b, lessThan(c.r * 0.6), reason: '$c 는 핑크·보라 쪽이다');
    }
  });

  test('옛 핑크·라일락 리터럴이 lib 어디에도 없다 — 색은 토큰에서만', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // 테마 고르기의 라일락 옵션은 남는다 — 기본이 아닐 뿐이다. 가족 구성원·케어 종류의 색
        // (`domain/pet.dart`)은 브랜드가 아니라 사람·종류를 가르는 팔레트라 그대로다.
        .where((f) => !RegExp(r'v2/(theme/themes|domain/pet)\.dart$')
            .hasMatch(f.path.replaceAll('\\', '/')));
    final hits = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final entry in _retired.entries) {
        if (src.contains(entry.key)) hits.add('${f.path}: ${entry.key} (${entry.value})');
      }
    }
    expect(hits, isEmpty, reason: '토큰 값을 바꿔도 이 자리는 옛 색으로 남는다:\n${hits.join('\n')}');
  });
}

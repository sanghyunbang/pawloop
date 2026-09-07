// 행정동 자산이 실제로 앱에 들어가는가 — 이슈 #342.
//
// ## 왜 파일을 읽어 재는가
//
// 이 목록이 없으면 동네 고르기 화면이 **빈 목록**이 된다. 그런데 그 실패는 조용하다 —
// `pubspec.yaml` 의 `assets:` 에서 한 줄이 빠져도 코드는 컴파일되고, 테스트도(자산을 안 쓰는
// 것들은) 초록이고, APK 도 만들어진다. 사용자만 빈 화면을 본다.
//
// 그래서 여기서는 **저장소의 파일을 직접 읽어** 개수와 모양을 세고, `pubspec.yaml` 에
// 그 경로가 적혀 있는지 함께 본다.
//
// ## 출처 표시
//
// 원자료는 통계청 SGIS(공공누리 1유형), 가공본은 vuski/admdongkor 로 **CC BY 4.0** 이다.
// 파생물에도 출처 표시 의무가 남으므로 파일 안의 `source` 와 화면의 한 줄이 함께 있어야
// 한다 — 화면 쪽은 `neighborhood_picker_test.dart` 가 잰다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/region_catalog.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('$path 가 없다 — 경로가 바뀌었으면 이 테스트도 함께 고친다');
  }
  return file.readAsStringSync();
}

void main() {
  late String raw;

  setUpAll(() => raw = _read(RegionCatalog.assetPath));

  test('전국이 다 들어 있다 — 시도 17 · 시군구 250 · 행정동 3,500 이상', () {
    final catalog = RegionCatalog.parse(raw);

    expect(catalog.sidos.length, 17, reason: '광역 17개가 다 있어야 한 단계가 완성된다');
    expect(catalog.all.length, greaterThanOrEqualTo(3500));
    expect(
      catalog.all.map((n) => n.sigunguCode).toSet().length,
      greaterThanOrEqualTo(250),
      reason: '시군구가 모자라면 그 지역 사람은 자기 동네를 못 고른다',
    );
  });

  test('아는 동을 코드로 찾을 수 있다 — 서울과 제주 양 끝', () {
    final catalog = RegionCatalog.parse(raw);

    // 실제 자료의 표기다 — '성수1가제1동' 이 아니라 '성수1가1동' 이다(실측).
    final seongsu = catalog.search('성수1가1동');
    expect(seongsu, isNotEmpty);
    expect(seongsu.first.sigungu, '성동구');
    expect(seongsu.first.code.length, 10, reason: '서버로 나가는 값이 열 자리다');

    expect(catalog.sidos, contains('제주특별자치도'));
    expect(catalog.sidos, contains('세종특별자치시'));
  });

  test('모든 동이 중심점을 든다 — 하나라도 0 이면 지도가 아프리카 앞바다로 간다', () {
    final catalog = RegionCatalog.parse(raw);

    final broken = catalog.all.where((n) => n.lat < 32 || n.lat > 40 || n.lng < 124 || n.lng > 132);

    expect(broken.map((n) => n.fullLabel).take(5), isEmpty,
        reason: '한반도 범위를 벗어난 중심점은 만드는 스크립트가 잘못된 것이다');
  });

  test('출처가 파일 안에 있다 — CC BY 4.0 은 파생물에도 표시를 요구한다', () {
    final json = jsonDecode(raw) as Map<String, dynamic>;

    expect(json['source'], contains('SGIS'));
    expect(json['source'], contains('CC BY 4.0'));
    expect(json['note'], contains('build_regions.py'),
        reason: '다시 만드는 방법이 파일 안에 있어야 한다');
  });

  test('pubspec 이 이 자산을 싣는다 — 빠지면 화면만 조용히 빈다', () {
    expect(_read('pubspec.yaml'), contains(RegionCatalog.assetPath));
  });

  test('만드는 스크립트가 저장소에 있다 — 원본 34MB 를 커밋하지 않는 대신', () {
    expect(File('tool/build_regions.py').existsSync(), isTrue);
  });
}

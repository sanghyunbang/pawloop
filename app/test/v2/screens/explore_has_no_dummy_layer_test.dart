// 지도 화면에 가짜 장소가 다시 들어오지 않는지 본다 — 이슈 #282 · #291.
//
// ## 왜 필요한가
//
// 성수동 근처의 가짜 병원·펫샵 5곳과 산책로 선 하나가 "예시" 라며 보이고 있었다.
// 부산 사용자가 병원 칩을 누르면 성수동의 가짜 병원이 떴다. #282 가 칩과 함께 내렸고,
// #291 이 실데이터(행정안전부 인허가 · 두루누비)로 칩을 되살렸다 — **칩은 돌아오되 가짜는
// 돌아오면 안 된다.**
//
// ## 왜 소스를 읽나
//
// 위젯 테스트는 네이버 지도 없이 이 화면을 못 띄운다. 그리고 상수 이름(`_dummyVet`)은
// 리팩터링으로 바뀔 수 있어도 **가짜 장소의 이름**은 그대로 돌아온다 — 그것을 잰다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/pet.dart';

const _layerKeys = ['vet', 'shop', 'trail'];

const _dummyMarks = [
  '서울숲동물병원',
  '성수24시동물의료센터',
  '한강동물병원',
  '멍냥마트',
  '보리네 펫살롱',
  '중랑천 물길 산책로',
  '_dummyVet',
  '_dummyShop',
  '_trailCoords',
  '공공데이터 (더미)',
  '예시 데이터',
];

void main() {
  test('지도 화면 소스에 가짜 장소가 없다', () {
    final file = File('lib/v2/screens/explore_screen.dart');
    if (!file.existsSync()) {
      fail('explore_screen.dart 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
    }
    final src = file.readAsStringSync();
    for (final mark in _dummyMarks) {
      expect(src.contains(mark), isFalse,
          reason: '"$mark" 가 돌아왔다 — 가짜 장소를 다시 보여 주는 코드다(#282)');
    }
  });

  test('병원·펫샵·산책로 칩이 실데이터 키로 돌아왔다 — 계약의 PlaceCategory 와 같은 아홉이다', () {
    final keys = kPetCategories.map((c) => c.key).toList();
    for (final k in _layerKeys) {
      expect(keys, contains(k), reason: '$k 칩은 #291 부터 실데이터다 — 서버가 카탈로그에 이어 붙인다');
    }
    expect(kLayerKeys, _layerKeys.toSet());
    expect(keys.toSet(), {'12', '39', '28', '32', '38', '14', ..._layerKeys},
        reason: '계약의 PlaceCategory enum 과 같은 집합이어야 한다');
  });

  test('레이어 키는 카테고리로 풀린다 — 모르는 키만 "기타" 다', () {
    expect(petCatByType('vet').label, '동물병원');
    expect(petCatByType('shop').label, '펫샵');
    expect(petCatByType('trail').label, '산책로');
    expect(petCatByType('99').label, '기타');
    expect(petCatByType(null).label, '기타');
  });

  test('화면은 카탈로그의 점을 그리고, 그림에 쓰는 가짜 좌표 상수가 없다', () {
    // 산책로의 선은 서버(`GET /api/places/trails/{courseId}/route`)에서 온다 — 화면에
    // 좌표 배열 리터럴이 있으면 누군가 다시 손으로 그린 것이다.
    final src = File('lib/v2/screens/explore_screen.dart').readAsStringSync();
    expect(src.contains('TrailRouteRepository'), isTrue,
        reason: '산책로 선은 저장소가 받아 온다(#291)');
    expect(RegExp(r'NLatLng\(\s*37\.\d+\s*,\s*127\.\d+\s*\)').allMatches(src).length, lessThanOrEqualTo(1),
        reason: '하드코딩된 좌표는 기본 중심(서울시청) 하나뿐이어야 한다');
  });
}

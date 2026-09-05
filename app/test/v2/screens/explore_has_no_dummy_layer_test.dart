// 지도 화면에 가짜 장소가 다시 들어오지 않는지 본다 — 이슈 #282.
//
// ## 왜 필요한가
//
// 성수동 근처의 가짜 병원·펫샵 5곳과 산책로 선 하나가 "예시" 라며 보이고 있었다.
// 부산 사용자가 병원 칩을 누르면 성수동의 가짜 병원이 떴다. 실데이터(LOCALDATA·두루누비)가
// 붙기 전에는 그 칩도 데이터도 없어야 한다.
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

  test('카테고리 목록에 병원·펫샵·산책로가 없다 — 칩은 목록에서 만들어진다', () {
    final keys = kPetCategories.map((c) => c.key).toList();
    for (final k in _layerKeys) {
      expect(keys, isNot(contains(k)),
          reason: '$k 칩이 돌아왔다면 실데이터가 붙은 것이어야 한다');
    }
  });
}

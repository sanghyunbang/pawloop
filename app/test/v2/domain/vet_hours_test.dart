// 동물병원 — 이름으로 짐작하는 24시 · 가까운 셋 고르기 (#337).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/domain/vet_hours.dart';

PetPlace _p(String title, {String source = 'vet', double dist = 0}) => PetPlace(
      contentId: title,
      title: title,
      source: source,
      category: source,
      contentTypeId: '',
      addr: '서울특별시 성동구',
      image: '',
      tel: '02-000-0000',
      lat: 37.5,
      lng: 127.0,
      distM: dist,
    );

void main() {
  group('이름으로 짐작하는 24시', () {
    test('이름에 24시가 있으면 참', () {
      expect(isTwentyFourHourByName('24시 서울숲동물병원'), isTrue);
      expect(isTwentyFourHourByName('성수24시동물의료센터'), isTrue);
      expect(isTwentyFourHourByName('24시간 응급 동물병원'), isTrue);
      expect(isTwentyFourHourByName('강남 24H 동물병원'), isTrue);
    });

    test('숫자만 24면 아니다 — 주소 조각을 24시로 읽지 않는다', () {
      expect(isTwentyFourHourByName('24번지 동물병원'), isFalse);
      expect(isTwentyFourHourByName('행복한 동물병원'), isFalse);
      expect(isTwentyFourHourByName('제이십사 동물병원'), isFalse);
    });

    test('가운뎃점·공백이 끼어도 읽는다', () {
      expect(isTwentyFourHourByName('24 시 동물병원'), isTrue);
      expect(isTwentyFourHourByName('24·시 동물병원'), isTrue);
    });
  });

  group('가까운 병원 셋', () {
    test('병원만, 가까운 순으로, 셋까지', () {
      final picks = nearestVets([
        _p('먼 병원', dist: 900),
        _p('카페', source: 'kto', dist: 10),
        _p('가까운 병원', dist: 120),
        _p('중간 병원', dist: 400),
        _p('네 번째 병원', dist: 1200),
      ]);
      expect(picks.map((p) => p.title).toList(), ['가까운 병원', '중간 병원', '먼 병원']);
    });

    test('거리를 모르는 곳은 뒤로 — 0m 로 맨 앞에 세우지 않는다', () {
      final picks = nearestVets([
        _p('거리 없음'),
        _p('300m 병원', dist: 300),
      ]);
      expect(picks.first.title, '300m 병원');
    });

    test('병원이 없으면 빈 목록', () {
      expect(nearestVets([_p('카페', source: 'kto', dist: 10)]), isEmpty);
    });
  });
}

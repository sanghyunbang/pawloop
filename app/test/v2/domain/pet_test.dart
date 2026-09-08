// 반려 도메인 모델의 순수 로직 테스트.
//
// 위젯이나 네트워크에 의존하지 않는 계산만 다룬다. 테스트 정책은 이슈 #21 참조.
import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

void main() {
  group('DogProfile.ageLabel', () {
    DogProfile withMonths(int m) => DogProfile(
          name: '보리',
          breed: '믹스견',
          size: DogSize.small,
          ageMonths: m,
        );

    test('12개월 미만은 개월로 표시한다', () {
      expect(withMonths(0).ageLabel, '0개월');
      expect(withMonths(1).ageLabel, '1개월');
      expect(withMonths(11).ageLabel, '11개월');
    });

    test('12개월부터는 살로 표시하고 내림한다', () {
      expect(withMonths(12).ageLabel, '1살');
      expect(withMonths(23).ageLabel, '1살');
      expect(withMonths(24).ageLabel, '2살');
      expect(withMonths(30).ageLabel, '2살');
    });

    test('11개월과 12개월 사이에서 표기가 바뀐다', () {
      expect(withMonths(11).ageLabel.endsWith('개월'), isTrue);
      expect(withMonths(12).ageLabel.endsWith('살'), isTrue);
    });
  });

  group('DogProfile.copyWith', () {
    const base = DogProfile(
      name: '보리',
      breed: '믹스견',
      size: DogSize.small,
      ageMonths: 30,
      neutered: true,
    );

    test('인자를 주지 않으면 값이 그대로 유지된다', () {
      final copy = base.copyWith();
      expect(copy.name, base.name);
      expect(copy.breed, base.breed);
      expect(copy.size, base.size);
      expect(copy.ageMonths, base.ageMonths);
      expect(copy.neutered, base.neutered);
    });

    test('준 인자만 바뀌고 나머지는 유지된다', () {
      final copy = base.copyWith(name: '치즈', ageMonths: 6);
      expect(copy.name, '치즈');
      expect(copy.ageMonths, 6);
      expect(copy.breed, base.breed);
      expect(copy.size, base.size);
      expect(copy.neutered, base.neutered);
    });

    test('neutered를 false로 되돌릴 수 있다', () {
      expect(base.copyWith(neutered: false).neutered, isFalse);
    });
  });

  group('petCatByType', () {
    test('KTO contenttypeid를 해당 카테고리로 해석한다', () {
      expect(petCatByType('12').label, '여행지');
      expect(petCatByType('39').label, '카페·식당');
      expect(petCatByType('32').label, '숙박');
    });

    test('병원·펫샵·산책로 key 는 실데이터 칩이다 — #282 가 내렸고 #291 이 되살렸다', () {
      expect(petCatByType('vet').label, '동물병원');
      expect(petCatByType('shop').label, '펫샵');
      expect(petCatByType('trail').label, '산책로');
      expect(kPetCategories.map((c) => c.key), containsAll(kLayerKeys));
    });

    test('모르는 값과 null은 기타로 떨어진다', () {
      expect(petCatByType('9999').label, '기타');
      expect(petCatByType(null).label, '기타');
      expect(petCatByType('').label, '기타');
    });

    test('카테고리 key 는 KTO contenttypeid(숫자) 아니면 레이어 키(kLayerKeys) 둘 중 하나다', () {
      for (final c in kPetCategories) {
        expect(int.tryParse(c.key) != null || kLayerKeys.contains(c.key), isTrue,
            reason: '${c.key} 는 KTO 도 공공데이터 레이어도 모르는 key 다');
      }
      expect(kLayerKeys, {'vet', 'shop', 'trail', 'playground'});
    });
  });

  group('kPetCategories', () {
    test('카테고리 key가 중복되지 않는다', () {
      final keys = kPetCategories.map((c) => c.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('모든 카테고리에 라벨이 있다', () {
      for (final c in kPetCategories) {
        expect(c.label, isNotEmpty, reason: 'key=${c.key}');
      }
    });
  });

  group('DogSize', () {
    test('각 크기에 한국어 라벨이 붙어 있다', () {
      expect(DogSize.small.label, '소형견');
      expect(DogSize.medium.label, '중형견');
      expect(DogSize.large.label, '대형견');
    });
  });
}

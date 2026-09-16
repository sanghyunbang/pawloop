// 사진이 없을 때의 얼굴 — 이슈 #585.
//
// ## 여기서 지키는 것
//
//  1. **열쇠말마다 그림 파일이 진짜 있다.** 목록은 코드에 있고 그림은 디스크에 있어서,
//     둘이 어긋나면 위젯 테스트는 초록인 채로 실기기에 깨진 그림 상자가 뜬다 — 테스트의
//     `Image.asset` 은 파일이 없어도 예외를 삼키기 때문이다.
//  2. **`pubspec.yaml` 이 그 폴더를 싣는다.** 안 실으면 디버그에서는 보이고 **릴리스에서만**
//     전부 빈 칸이 된다.
//  3. **모르는 열쇠말은 떨어진다.** 서버가 DB 제약을 안 걸어서(#586) 새 앱이 고른 값이 옛
//     앱에 온다. 그때 종류 기본 그림으로 가야지, 홈 한가운데가 깨지면 안 된다.
//  4. **사본 메서드가 값을 안 떨어뜨린다.** 필드를 손으로 나열하는 자리의 실패 모드다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/domain/pet_characters.dart';

const _bori = DogProfile(
  serverId: 7,
  name: '보리',
  breed: '믹스견',
  size: DogSize.small,
  ageMonths: 30,
);

void main() {
  test('열쇠말 열셋 — 서버 PetCharacter 와 같은 목록이다', () {
    expect(kPetCharacterKeys, hasLength(13));
    expect(kPetCharacterKeys.toSet(), hasLength(13), reason: '같은 열쇠말이 두 번 있으면 줄에 같은 칸이 둘 선다');
  });

  test('열쇠말마다 그림 파일이 진짜 있다', () {
    final missing = [
      for (final key in kPetCharacterKeys)
        if (!File('assets/emoji/$key.png').existsSync()) key,
    ];
    expect(missing, isEmpty,
        reason: '목록에만 있고 파일이 없으면 그 칸은 실기기에서 깨진 그림 상자가 된다');
  });

  test('pubspec 이 emoji 폴더를 싣는다 — 안 실으면 릴리스에서만 빈 칸이다', () {
    // **줄을 읽는다.** 처음엔 파일 전체에 그 글자가 있는지만 봤는데, 목록에서 빼고 주석으로
    // 남겨도 초록이었다 — 주석에도 같은 글자가 있어서다. 검사가 아무것도 안 보는 상태였다.
    final entries = [
      for (final line in File('pubspec.yaml').readAsLinesSync())
        if (RegExp(r'^\s*-\s*assets/emoji/\s*$').hasMatch(line)) line,
    ];
    expect(entries, hasLength(1),
        reason: '`- assets/emoji/` 한 줄이 목록에 있어야 한다 — 주석은 안 싣는다');
  });

  test('종류 기본 그림도 파일이 있다 — 고른 얼굴이 없을 때 여기로 떨어진다', () {
    for (final species in PetSpecies.values) {
      expect(File(petSpeciesAsset(species)).existsSync(), isTrue,
          reason: '${species.name} 의 기본 그림이 없다: ${petSpeciesAsset(species)}');
    }
  });

  test('모르는 열쇠말은 null 이다 — 옛 앱에 새 얼굴이 와도 안 깨진다', () {
    expect(petCharacterAsset('dragon'), isNull);
    expect(petCharacterAsset(null), isNull);
    expect(petCharacterAsset('poodle'), 'assets/emoji/poodle.png');
  });

  test('열쇠말마다 이름이 있다 — 그림만으로 안 갈리는 칸이 있다', () {
    for (final key in kPetCharacterKeys) {
      expect(petCharacterLabel(key), isNot('기타'), reason: '$key 의 이름이 빠졌다');
    }
    expect(petCharacterLabel('dog_face'), isNot(petCharacterLabel('dog')),
        reason: '둘 다 강아지라 이름까지 같으면 고르기 줄에서 못 가른다');
  });

  group('아바타 그림의 순서', () {
    test('고른 얼굴이 종류 기본을 이긴다', () {
      expect(_bori.copyWith(characterKey: 'poodle').avatarAsset, 'assets/emoji/poodle.png');
    });

    test('안 골랐으면 종류 기본이다 — 옛 아이의 화면이 안 바뀐다', () {
      expect(_bori.avatarAsset, petSpeciesAsset(PetSpecies.dog));
    });

    test('모르는 얼굴이면 종류 기본으로 떨어진다', () {
      expect(_bori.copyWith(characterKey: 'dragon').avatarAsset, petSpeciesAsset(PetSpecies.dog));
    });
  });

  group('사본 메서드', () {
    test('다른 것을 고쳐도 고른 얼굴이 남는다', () {
      final chosen = _bori.copyWith(characterKey: 'hedgehog');
      expect(chosen.copyWith(name: '보리야').characterKey, 'hedgehog',
          reason: '여기서 빠뜨리면 이름 한 번 고칠 때마다 얼굴이 기본으로 돌아간다');
    });

    test('깃발로만 지워진다 — null 은 "안 바꿈" 이다', () {
      final chosen = _bori.copyWith(characterKey: 'hedgehog');
      expect(chosen.copyWith(characterKey: null).characterKey, 'hedgehog');
      expect(chosen.copyWith(clearCharacter: true).characterKey, isNull);
    });
  });
}

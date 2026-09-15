// 지도 핀 그림은 카테고리마다 한 번만 굽는다 — 이슈 #533.
//
// 장소마다 구웠을 때 서울숲 주변 80곳에서 **31.7초 중 31.5초(99%)** 가 그 시간이었다.
// 지도 타일은 6초에 왔는데 핀은 20초가 넘어서야 한꺼번에 나타났다.
//
// 여기서 `NOverlayImage` 는 안 만든다 — 플러그인이라 순수 테스트에서 못 부른다. `MarkerIcons`
// 가 그림 타입을 모르게 만든 이유가 이것이다. 굽는 일을 문자열로 바꿔 끼우고 **몇 번 불렀는지**
// 를 센다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/widgets/marker_icons.dart';

void main() {
  /// 굽는 횟수를 세는 가짜. 카테고리 이름을 그림 삼아 돌려준다.
  ({MarkerIcons<String> icons, List<String> drew}) subject({
    Completer<String>? hold,
    bool fail = false,
  }) {
    final drew = <String>[];
    return (
      drew: drew,
      icons: MarkerIcons<String>((cat) async {
        drew.add(cat.key);
        if (fail) throw StateError('못 구웠다');
        if (hold != null) return hold.future;
        return 'icon:${cat.key}';
      }),
    );
  }

  /// 서울숲 주변에서 본 것과 같은 모양 — 장소는 많고 종류는 적다.
  List<PetCategory> eightyPlaces() => [
        for (var i = 0; i < 80; i++) kPetCategories[i % kPetCategories.length],
      ];

  test('장소가 80곳이어도 그림은 카테고리 수만큼만 굽는다', () async {
    final s = subject();

    for (final cat in eightyPlaces()) {
      await s.icons.of(cat);
    }

    expect(s.drew, hasLength(kPetCategories.length),
        reason: '80곳을 돌면서 같은 그림을 다시 구우면 한 개에 약 393ms 씩 31초가 든다(#533)');
    expect(s.icons.baked, kPetCategories.length);
  });

  test('같은 카테고리는 같은 그림을 돌려준다', () async {
    final s = subject();
    final vet = petCatByType('vet');

    expect(await s.icons.of(vet), 'icon:vet');
    expect(await s.icons.of(vet), 'icon:vet');
    expect(s.drew, ['vet']);
  });

  test('같은 카테고리를 동시에 물어도 한 번만 굽는다', () async {
    // 굽는 일이 안 끝난 채로 두 번째가 온다 — 끝난 그림만 담으면 여기서 또 굽는다.
    final hold = Completer<String>();
    final s = subject(hold: hold);
    final cafe = petCatByType('39');

    final first = s.icons.of(cafe);
    final second = s.icons.of(cafe);
    hold.complete('icon:39');

    expect(await first, 'icon:39');
    expect(await second, 'icon:39');
    expect(s.drew, ['39'], reason: '굽고 있는 것을 담아야 두 번째가 그것을 기다린다');
  });

  test('못 구운 것은 기억하지 않는다 — 다음에 다시 해 본다', () async {
    final failing = subject(fail: true);
    await expectLater(failing.icons.of(petCatByType('trail')), throwsStateError);

    // 실패를 담아 두면 그 카테고리는 영영 핀이 없다.
    expect(failing.icons.baked, 0);
    await expectLater(failing.icons.of(petCatByType('trail')), throwsStateError);
    expect(failing.drew, ['trail', 'trail']);
  });

  test('모르는 카테고리(기타)도 한 자리를 쓴다 — 키가 없으면 매번 굽는다', () async {
    final s = subject();
    final other = petCatByType('없는-키');

    await s.icons.of(other);
    await s.icons.of(petCatByType('또-없는-키'));

    expect(other.label, '기타');
    expect(s.drew, ['0'], reason: 'petCatByType 이 모르는 키를 전부 같은 기타로 접는다');
  });
}

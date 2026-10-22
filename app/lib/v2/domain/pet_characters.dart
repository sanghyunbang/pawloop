// lib/v2/domain/pet_characters.dart
//
// 사진이 없을 때의 아이 얼굴 — 이슈 #585.
//
// ## 왜 있나
//
// 얼굴이 **종류당 하나**였다 — 강아지면 모두 같은 그림. 사진을 안 올린 집은 아이가 둘이어도
// 홈의 고르기 칩이 같은 얼굴 둘로 서고, 이름을 읽기 전에는 못 가른다. 사진을 강요할 수는
// 없으니(2026-09-16) 고를 얼굴을 준다.
//
// ## 열쇠말이 곧 파일 이름이다
//
// `assets/emoji/<열쇠말>.png` 하나로 끝난다 — 예외표를 두지 않는다. 표를 두면 열쇠말을 더할
// 때 두 곳을 고쳐야 하고, 한 곳만 고친 날 그림이 조용히 안 나온다.
//
// 그 규칙을 지키려고 옛 파일 둘의 이름을 바꿨다. `dog.png` 는 🐶(얼굴)이고 🐕(온몸)은 따로
// 있어서, 얼굴 쪽이 `dog_face.png` 가 됐다. `cat.png` 도 같다.
//
// ## 모르는 열쇠말은 떨어뜨린다
//
// 서버는 이 값에 DB 제약을 안 건다(#586) — 목록이 여기서 늘고 주는 화면의 목록이라서다.
// 그래서 **새 앱에서 고른 값이 옛 앱에 올 수 있다.** 그때 `Image.asset` 은 깨진 그림 상자를
// 홈 한가운데에 그린다. 모르면 `null` 을 주고 부르는 쪽이 종류 기본 그림으로 간다 — 그림
// 하나가 밋밋한 것과 화면이 깨지는 것은 무게가 다르다.
library;

/// 고를 수 있는 얼굴 — 서버 `PetCharacter` 와 **같은 열셋, 같은 순서**다.
///
/// 순서가 곧 고르기 줄의 순서다. 강아지·고양이를 앞에 두는 이유는 지금 등록된 아이가
/// 그 둘이기 때문이고, 뒤쪽은 "강아지가 아닌 아이" 를 키우는 사람을 위한 자리다.
const List<String> kPetCharacterKeys = [
  'dog_face',
  'dog',
  'poodle',
  'cat_face',
  'cat',
  'black_cat',
  'rabbit',
  'hamster',
  'bird',
  'parrot',
  'turtle',
  'hedgehog',
  'paw',
];

/// 그 얼굴의 그림. **모르는 열쇠말이면 `null`** — 머리말의 이유다.
String? petCharacterAsset(String? key) =>
    key != null && kPetCharacterKeys.contains(key) ? 'assets/emoji/$key.png' : null;

/// 고르기 줄에 적히는 이름. 그림만으로 안 갈리는 둘(🐶/🐕, 🐱/🐈/🐈‍⬛)은 색으로 가른다.
String petCharacterLabel(String key) => switch (key) {
      'dog_face' => '강아지',
      'dog' => '누렁이',
      'poodle' => '푸들',
      'cat_face' => '고양이',
      'cat' => '치즈',
      'black_cat' => '까망',
      'rabbit' => '토끼',
      'hamster' => '햄스터',
      'bird' => '새',
      'parrot' => '앵무새',
      'turtle' => '거북이',
      'hedgehog' => '고슴도치',
      'paw' => '발바닥',
      _ => '기타',
    };

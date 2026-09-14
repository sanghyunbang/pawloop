// lib/v2/data/pet_sync.dart
//
// 반려동물 목록을 서버와 맞춘다 — 이슈 #159.
//
// ## 왜 필요한가
//
// `registerPet` 이 `walk_repository.dart` 에 **정의만 되고 아무도 안 불렀다.** 그래서
// 서버에 한 마리도 없는 사용자가 산책을 저장하면
//
//   walk_sync.dart  _firstPetId() → pets() 가 빈 배열 → StateError
//   → "반려동물을 등록하면 이 산책을 올릴게요" 로 큐에 남음
//
// 이 되는데, **등록할 화면이 없어서 영원히 거기 있었다.** 동시에 화면은 하드코딩된
// '보리'·'치즈' 를 "우리 아이" 로 보여 줬다 — 화면과 안내가 서로 다른 말을 했다.
//
// ## 여기가 유일한 출처다
//
// `kMyPets` 를 바꾸는 곳은 이 파일뿐이다. 화면이 각자 `ValueNotifier` 를 갈아 끼우면
// "서버에 있는 것" 과 "화면에 있는 것" 이 갈라지고, 그게 위의 사고를 만든 모양이다.
library;

import 'package:flutter/foundation.dart';

import '../domain/pet.dart';
import 'walk_repository.dart';

/// 서버의 반려동물과 앱의 [kMyPets] 를 맞춘다.
class PetSync {
  final WalkRepository _repo;

  PetSync({WalkRepository? repository}) : _repo = repository ?? WalkRepository();

  /// 서버 목록을 불러 [kMyPets] 를 갈아 끼운다.
  ///
  /// **실패하면 아무것도 안 바꾼다.** 연결이 끊겼다고 화면에서 아이가 사라지면
  /// 사용자는 등록이 풀린 줄 안다.
  ///
  /// @return 불러왔으면 `true`. 실패했으면 `false` — 화면은 그때 마지막으로 본 것을
  ///         그대로 그린다
  Future<bool> load() async {
    try {
      final pets = await _repo.pets();
      replacePets(pets.map(_toProfile).toList());
      return true;
    } on WalkFailure {
      return false;
    }
  }

  /// 한 마리 등록하고 목록을 갱신한다.
  ///
  /// 성공하면 **그 아이가 선택된 상태**가 된다 — 방금 등록한 사람이 바로 보고 싶은 것이다.
  ///
  /// @throws WalkFailure 서버가 거절했거나 연결이 없을 때. 부르는 쪽이 문구를 보여 준다
  Future<DogProfile> register({
    required String name,
    required PetSpecies species,
    required DogSize size,
    String? breed,
  }) async {
    final saved = await _repo.registerPet(
      name: name,
      species: _toServerSpecies(species),
      size: _toServerSize(size),
      breed: breed,
    );
    final profile = _toProfile(saved);
    replacePets([...kMyPets.value, profile]);
    selectPet(kMyPets.value.length - 1);
    return profile;
  }

  /// 한 마리를 보낸다 — 서버는 소프트 삭제라 **산책 기록은 남고 통계에도 계속 센다**(#156).
  ///
  /// 성공하면 목록에서 빠지고 선택은 남은 아이 중 하나로 옮긴다([replacePets] 가 한다).
  /// **되살리기는 없다** — 그래서 부르는 쪽의 확인 문구가 그만큼 분명해야 한다.
  /// 서버가 모르는 아이(`serverId` 가 null)는 화면에서만 뺀다.
  ///
  /// @throws WalkFailure 서버가 거절했거나 연결이 없을 때. 목록은 그대로다 — 실패했는데
  ///         화면에서 사라지면 사용자는 지워진 줄 안다
  Future<void> remove(DogProfile pet) async {
    final id = pet.serverId;
    if (id != null) {
      await _repo.deletePet(id);
    }
    replacePets(
      kMyPets.value.where((p) => id == null ? !identical(p, pet) : p.serverId != id).toList(),
    );
    notifyPetsChanged();
  }

  /// 로그아웃했다. **화면에서 지운다** — 다음 사람이 남의 아이를 보면 안 된다.
  static void clear() => replacePets(const []);

  // ─────────────────────────── 변환 ───────────────────────────
  //
  // 서버 모델(ServerPet)과 화면 모델(DogProfile)이 따로 있는 이유: 화면 쪽은 아바타
  // 에셋·나이 라벨 같은 표시용 파생을 들고, 서버 쪽은 계약의 키를 그대로 읽는다.
  // 둘을 하나로 합치면 계약이 바뀔 때마다 화면이 흔들린다.

  /// 프로필 사진을 붙이거나(#448) 뗀다. 서버가 돌려준 아이로 목록의 그 자리를 갈아 끼운다 —
  /// 응답의 `avatarUrl` 을 그대로 그리지, 로컬에서 URL 을 짓지 않는다.
  Future<DogProfile> setPhoto(DogProfile pet, int mediaId) async {
    final id = pet.serverId;
    if (id == null) throw const WalkFailure(WalkFailureKind.notFound);
    return _swap(_toProfile(await _repo.setPetAvatar(id, mediaId)));
  }

  Future<DogProfile> clearPhoto(DogProfile pet) async {
    final id = pet.serverId;
    if (id == null) throw const WalkFailure(WalkFailureKind.notFound);
    return _swap(_toProfile(await _repo.clearPetAvatar(id)));
  }

  DogProfile _swap(DogProfile fresh) {
    replacePets([
      for (final p in kMyPets.value) p.serverId == fresh.serverId ? fresh : p,
    ]);
    return fresh;
  }

  static DogProfile _toProfile(ServerPet pet) => DogProfile(
        serverId: pet.id,
        name: pet.name,
        breed: pet.breed ?? '',
        species: switch (pet.species) {
          ServerPetSpecies.dog => PetSpecies.dog,
          ServerPetSpecies.cat => PetSpecies.cat,
          ServerPetSpecies.other => PetSpecies.other,
        },
        size: switch (pet.size) {
          ServerPetSize.small => DogSize.small,
          ServerPetSize.medium => DogSize.medium,
          ServerPetSize.large => DogSize.large,
        },
        // 서버는 생일에서 개월을 파생한다. 모르면 null 인데 화면 모델은 int 라
        // 0 으로 눕힌다 — ageLabel 이 "0개월" 을 그리므로, 생일을 안 받는 지금은
        // 그게 "모른다" 와 같은 자리다. 생일 입력을 받는 날 이 줄을 다시 본다.
        ageMonths: pet.ageMonths ?? 0,
        neutered: pet.neutered,
        photoUrl: pet.avatarUrl,
      );

  static ServerPetSpecies _toServerSpecies(PetSpecies s) => switch (s) {
        PetSpecies.dog => ServerPetSpecies.dog,
        PetSpecies.cat => ServerPetSpecies.cat,
        PetSpecies.other => ServerPetSpecies.other,
      };

  static ServerPetSize _toServerSize(DogSize s) => switch (s) {
        DogSize.small => ServerPetSize.small,
        DogSize.medium => ServerPetSize.medium,
        DogSize.large => ServerPetSize.large,
      };
}

/// 반려동물 목록을 다시 불러야 한다는 신호.
///
/// 등록·삭제가 일어나면 값이 하나 오른다. `walk_feed.dart` 의 `walkFeedRevision` 과
/// 같은 장치다 — 화면마다 "돌아왔을 때 다시 불러오기" 를 손으로 붙이면 한 곳을
/// 빠뜨리는 날이 온다.
final ValueNotifier<int> petRevision = ValueNotifier<int>(0);

void notifyPetsChanged() => petRevision.value++;

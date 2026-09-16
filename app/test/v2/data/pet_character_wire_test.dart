// 고른 얼굴이 서버까지 갔다가 돌아온다 — 이슈 #585.
//
// ## 여기서 지키는 것
//
//  1. **등록할 때 고른 값이 본문에 실린다.** 안 실리면 고르고 저장해도 안 남는다.
//  2. **안 고른 사람의 본문에는 그 키가 아예 없다.** `null` 을 실으면 서버가 "지워 달라" 로
//     읽는데, 등록에는 지울 것이 없어 뜻이 없는 말이 된다.
//  3. **지우기는 `null` 을 보내야 된다.** 안 보내면 "안 바꿈" 이라 한 번 고른 사람은 종류
//     기본 그림으로 못 돌아간다 — `birth` 와 같은 규약이다(#586).
//  4. **응답의 값이 화면 모델까지 온다.** 서버 답을 화면 모델로 옮기는 자리가 필드를
//     떨어뜨리면, 저장은 되는데 화면이 계속 옛 얼굴을 그린다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'AT-1';
  @override
  Future<String?> readRefreshToken() async => 'RT-1';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

/// 계약의 `Dog` 그대로. **앱이 읽는 키가 아니라 계약의 키로 짓는다** — 앱이 틀린 키를 읽고
/// 있으면 목을 앱에 맞춘 테스트가 그 버그에 동의한다(#82).
String _dogJson({String? character}) => jsonEncode({
      'id': 7,
      'name': '보리',
      'species': 'dog',
      'breed': '믹스견',
      'size': 'small',
      'birth': null,
      'ageMonths': 30,
      'neutered': false,
      'avatarUrl': null,
      'character': character,
      'mine': true,
    });

({PetSync sync, List<Map<String, Object?>> bodies}) fixture({String? answers}) {
  final bodies = <Map<String, Object?>>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return http.Response('{}', 404, headers: const {'content-type': 'application/json'});
      }
      if (request.body.isNotEmpty) {
        bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      }
      return http.Response(answers ?? _dogJson(), request.method == 'POST' ? 201 : 200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    sync: PetSync(
      repository: WalkRepository(baseUrl: _base, client: client),
      family: FamilyRepository(baseUrl: _base, client: client),
    ),
    bodies: bodies,
  );
}

void main() {
  setUp(() => replacePets(const []));

  test('등록할 때 고른 얼굴이 본문에 실린다', () async {
    final f = fixture(answers: _dogJson(character: 'poodle'));

    final saved = await f.sync.register(
      name: '보리',
      species: PetSpecies.dog,
      size: DogSize.small,
      character: 'poodle',
    );

    expect(f.bodies.single['character'], 'poodle');
    expect(saved.characterKey, 'poodle', reason: '서버가 돌려준 값이 화면 모델까지 와야 한다');
    expect(saved.avatarAsset, 'assets/emoji/poodle.png');
  });

  test('안 골랐으면 그 키를 아예 안 보낸다', () async {
    final f = fixture();

    await f.sync.register(name: '보리', species: PetSpecies.dog, size: DogSize.small);

    expect(f.bodies.single.containsKey('character'), isFalse,
        reason: '등록에는 지울 것이 없다 — null 은 "지워 달라" 라 뜻이 없는 말이 된다');
  });

  test('나중에 고르면 부분 수정에 실린다', () async {
    final f = fixture(answers: _dogJson(character: 'hedgehog'));
    replacePets(const [DogProfile(serverId: 7, name: '보리', breed: '', size: DogSize.small, ageMonths: 0)]);

    final saved = await f.sync.edit(7, character: 'hedgehog');

    expect(f.bodies.single['character'], 'hedgehog');
    expect(saved.characterKey, 'hedgehog');
    expect(kMyPets.value.single.characterKey, 'hedgehog',
        reason: '목록의 그 아이도 갈아끼워야 홈이 새 얼굴을 그린다');
  });

  test('지울 때는 null 을 **보낸다** — 안 보내면 "안 바꿈" 이다', () async {
    final f = fixture();

    await f.sync.edit(7, clearCharacter: true);

    expect(f.bodies.single.containsKey('character'), isTrue);
    expect(f.bodies.single['character'], isNull,
        reason: '한 번 고른 사람이 종류 기본 그림으로 돌아갈 길이 이것뿐이다');
  });

  test('다른 것만 고치면 그 키가 본문에 없다', () async {
    final f = fixture();

    await f.sync.edit(7, name: '보리야');

    expect(f.bodies.single.keys, ['name'],
        reason: '안 보낸 것은 서버가 그대로 둔다 — 두 기기가 서로의 편집을 덮지 않는 이유다');
  });

  test('목록을 읽을 때도 실린다 — 엄마가 고른 얼굴을 아빠도 본다', () async {
    final f = fixture(answers: '[${_dogJson(character: 'black_cat')}]');

    await f.sync.load();

    expect(kMyPets.value.single.characterKey, 'black_cat');
    expect(kMyPets.value.single.avatarAsset, 'assets/emoji/black_cat.png');
  });

  test('옛 서버는 그 키를 안 보낸다 — 그래도 한 줄이 통째로 사라지지 않는다', () async {
    final f = fixture(answers: jsonEncode([
      {
        'id': 7,
        'name': '보리',
        'species': 'dog',
        'size': 'small',
        'neutered': false,
      }
    ]));

    await f.sync.load();

    expect(kMyPets.value.single.name, '보리');
    expect(kMyPets.value.single.characterKey, isNull);
  });

  test('모르는 열쇠말이 와도 아이는 남는다 — 그림만 기본으로 떨어진다', () async {
    final f = fixture(answers: '[${_dogJson(character: 'dragon')}]');

    await f.sync.load();

    expect(kMyPets.value.single.name, '보리',
        reason: '여기서 막으면 새 앱이 고른 얼굴 하나에 아이 한 줄이 사라진다');
    expect(kMyPets.value.single.avatarAsset, petSpeciesAsset(PetSpecies.dog));
  });
}

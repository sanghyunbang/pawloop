// PetSync — 서버의 반려동물과 kMyPets 를 맞춘다 (이슈 #159).
//
// ## 여기서 지키는 것
//
//  1. **하드코딩된 아이가 없다.** 예전에는 '보리'·'치즈' 두 마리가 상수로 있어서, 서버에
//     0마리인 사용자에게도 "우리 아이 2마리" 를 보여 줬다. 그러고는 산책을 저장할 때
//     "반려동물을 등록하면 올릴게요" 라고 말했다 — 화면과 안내가 다른 말을 했다.
//  2. **실패하면 아무것도 안 바꾼다.** 연결이 끊겼다고 아이가 사라지면 사용자는 등록이
//     풀린 줄 안다.
//  3. **로그아웃하면 지운다.** 다음 사람이 앞사람의 아이를 보면 안 된다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  String? access = 'access-token';
  String? refresh = 'refresh-token';

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

({PetSync sync, List<http.Request> seen}) syncThatAnswers(
  http.Response Function(http.Request request) answer,
) {
  final seen = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add(request);
      return answer(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (
    sync: PetSync(repository: WalkRepository(baseUrl: _base, client: client)),
    seen: seen,
  );
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 계약의 `Dog` 그대로.
Map<String, Object?> dogJson({int id = 1, String name = '보리', String species = 'dog'}) => {
      'id': id,
      'name': name,
      'species': species,
      'breed': '믹스견',
      'size': 'small',
      'birth': null,
      'ageMonths': 30,
      'neutered': true,
      'avatarUrl': null,
    };

void main() {
  setUp(() {
    // 각 테스트는 빈 상태에서 시작한다.
    replacePets(const []);
  });

  test('앱은 하드코딩된 아이 없이 시작한다 — 서버가 유일한 출처다', () {
    expect(kMyPets.value, isEmpty,
        reason: "예전에는 '보리'·'치즈' 가 상수로 있어서 서버에 0마리인 사람도 2마리를 봤다");
    expect(kMyDog.value, isNull);
  });

  test('서버 목록을 kMyPets 로 옮기고 첫 마리를 선택한다', () async {
    final r = syncThatAnswers((_) => _json([
          dogJson(id: 7, name: '보리'),
          dogJson(id: 9, name: '나비', species: 'cat'),
        ]));

    final ok = await r.sync.load();

    expect(ok, isTrue);
    expect(kMyPets.value.map((p) => p.name), ['보리', '나비']);
    expect(kMyDog.value!.name, '보리');
    expect(kMyDog.value!.serverId, 7,
        reason: '산책을 저장하려면 이 id 가 필요하다 — 계약의 WalkInput.dogId 는 필수다');
    expect(kMyPets.value[1].species, PetSpecies.cat,
        reason: '고양이가 개로 보이면 안 된다');
  });

  test('서버가 빈 배열을 주면 선택도 비운다', () async {
    final r = syncThatAnswers((_) => _json([]));

    await r.sync.load();

    expect(kMyPets.value, isEmpty);
    expect(kMyDog.value, isNull,
        reason: '지어낸 프로필을 남기면 사용자는 등록이 끝난 줄 안다');
  });

  test('불러오기에 실패하면 아무것도 안 바꾼다 — 아이가 사라지면 안 된다', () async {
    final loaded = syncThatAnswers((_) => _json([dogJson(id: 7)]));
    await loaded.sync.load();
    expect(kMyDog.value!.name, '보리');

    final failing = syncThatAnswers((_) => _json({}, status: 500));
    final ok = await failing.sync.load();

    expect(ok, isFalse);
    expect(kMyDog.value!.name, '보리',
        reason: '연결이 끊겼다고 화면에서 아이가 사라지면 등록이 풀린 줄 안다');
  });

  test('등록하면 계약대로 보내고, 그 아이가 선택된다', () async {
    final r = syncThatAnswers((req) {
      if (req.method == 'POST') return _json(dogJson(id: 3, name: '나비', species: 'cat'), status: 201);
      return _json([]);
    });

    final saved = await r.sync.register(
      name: '나비',
      species: PetSpecies.cat,
      size: DogSize.small,
      breed: '코숏',
    );

    final post = r.seen.singleWhere((q) => q.method == 'POST');
    expect(post.url.path, '/api/dogs');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['species'], 'cat', reason: '계약이 정한 소문자 그대로여야 한다');
    expect(body['size'], 'small');
    expect(body['name'], '나비');

    expect(saved.serverId, 3);
    expect(kMyDog.value!.name, '나비', reason: '방금 등록한 아이가 선택돼야 한다');
    expect(kMyPets.value, hasLength(1));
  });

  test('등록 실패는 던진다 — 화면이 이유를 보여 줘야 한다', () async {
    final r = syncThatAnswers((_) => _json({}, status: 400));

    await expectLater(
      r.sync.register(name: '나비', species: PetSpecies.cat, size: DogSize.small),
      throwsA(isA<WalkFailure>()
          .having((f) => f.kind, 'kind', WalkFailureKind.rejected)),
    );
    expect(kMyPets.value, isEmpty, reason: '실패한 등록이 목록에 남으면 안 된다');
  });

  test('한 마리를 보내면 DELETE 를 부르고 목록에서 빠지며 남은 아이가 선택된다 (#156)', () async {
    final s = syncThatAnswers((req) => req.method == 'DELETE'
        ? http.Response('', 204)
        : _json([dogJson(id: 1, name: '보리'), dogJson(id: 2, name: '탄이')]));
    await s.sync.load();
    expect(kMyPets.value, hasLength(2));

    await s.sync.remove(kMyPets.value.first);

    expect(s.seen.last.method, 'DELETE');
    expect(s.seen.last.url.path, '/api/dogs/1');
    expect(kMyPets.value.map((p) => p.name), ['탄이']);
    expect(kMyDog.value?.name, '탄이', reason: '보낸 아이가 선택된 채 남아 있으면 안 된다');
  });

  test('보내기에 실패하면 던지고 목록은 그대로다 — 실패했는데 사라지면 지워진 줄 안다', () async {
    final s = syncThatAnswers((req) => req.method == 'DELETE'
        ? _json({'error': {}}, status: 404)
        : _json([dogJson(id: 1, name: '보리')]));
    await s.sync.load();

    await expectLater(
      s.sync.remove(kMyPets.value.first),
      throwsA(isA<WalkFailure>()
          .having((f) => f.kind, 'kind', WalkFailureKind.notFound)),
    );
    expect(kMyPets.value.map((p) => p.name), ['보리']);
  });

  test('로그아웃하면 지운다 — 다음 사람이 앞사람의 아이를 보면 안 된다', () async {
    final r = syncThatAnswers((_) => _json([dogJson(id: 7)]));
    await r.sync.load();
    expect(kMyPets.value, isNotEmpty);

    PetSync.clear();

    expect(kMyPets.value, isEmpty);
    expect(kMyDog.value, isNull);
  });
}

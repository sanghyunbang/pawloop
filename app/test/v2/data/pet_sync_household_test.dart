// PetSync 가 **우리 집 아이**를 읽는다 — 이슈 #563.
//
// ## 무엇이 있었나
//
// 이 앱의 목적은 업무 분담과 누락 방지다(#76). 그런데 앱이 `GET /api/dogs`(내가 등록한
// 아이)만 읽어서, 엄마가 보리를 등록하고 아빠가 가족에 들어와도 **아빠 홈은 "아직 등록된
// 아이가 없어요"** 였다. 아빠가 보리를 또 등록하면 같은 아이가 두 마리가 되고 케어 기록이
// 둘로 갈린다.
//
// ## 여기서 지키는 것
//
//  1. 가족이 있으면 **집 아이**를 읽는다 — 남이 등록한 아이가 섞여 온다.
//  2. 남이 등록한 아이는 `mine == false` 다 — 화면이 이 값으로 "고칠 수 있나" 를 가른다.
//  3. **가족을 못 읽어도 화면이 안 빈다.** 가족이 없든 연결이 끊겼든 내 아이로 돌아간다 —
//     아이 목록이 통째로 사라지는 것이 더 나쁜 실패다.
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

class _Tokens implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'a';
  @override
  Future<String?> readRefreshToken() async => 'r';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body), status,
      headers: const {'content-type': 'application/json; charset=utf-8'});

/// 계약의 `Dog` 그대로 — `mine` 포함(#563).
Map<String, Object?> _dog({
  required int id,
  required String name,
  bool mine = true,
}) =>
    {
      'id': id,
      'name': name,
      'species': 'dog',
      'breed': '믹스견',
      'size': 'small',
      'birth': null,
      'ageMonths': 30,
      'neutered': true,
      'avatarUrl': null,
      'mine': mine,
    };

({PetSync sync, List<String> seen}) syncThatAnswers(
    http.Response Function(http.Request request) answer) {
  final seen = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      seen.add('${request.method} ${request.url.path}');
      return answer(request);
    }),
    baseUrl: _base,
    store: _Tokens(),
  );
  return (
    sync: PetSync(
      repository: WalkRepository(baseUrl: _base, client: client),
      family: FamilyRepository(baseUrl: _base, client: client),
    ),
    seen: seen,
  );
}

void main() {
  setUp(() => replacePets(const []));

  test('가족이 있으면 집 아이를 읽는다 — 남이 등록한 아이가 섞여 온다 (#563)', () async {
    final f = syncThatAnswers((request) {
      if (request.url.path == '/api/groups/me') {
        return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
      }
      if (request.url.path == '/api/groups/3/dogs') {
        return _json([
          _dog(id: 1, name: '보리', mine: false),
          _dog(id: 2, name: '뭉치'),
        ]);
      }
      return _json(const []);
    });

    expect(await f.sync.load(), isTrue);

    expect(kMyPets.value.map((p) => p.name), ['보리', '뭉치'],
        reason: '이 목록이 비어 있던 동안 가족에 합류한 아빠 홈은 "아직 등록된 아이가 없어요" 였다');
    expect(f.seen, contains('GET /api/groups/3/dogs'));
    expect(f.seen, isNot(contains('GET /api/dogs')),
        reason: '가족이 있으면 내 아이 목록은 안 부른다 — 왕복 하나가 그냥 낭비다');
  });

  test('남이 등록한 아이는 mine=false 다 — 화면이 이 값으로 고치기를 가른다', () async {
    final f = syncThatAnswers((request) {
      if (request.url.path == '/api/groups/me') {
        return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
      }
      return _json([
        _dog(id: 1, name: '보리', mine: false),
        _dog(id: 2, name: '뭉치'),
      ]);
    });

    await f.sync.load();

    expect(kMyPets.value.map((p) => p.mine), [false, true]);
  });

  test('가족이 없으면 내 아이로 간다 — 1인 사용자의 화면은 그대로다', () async {
    final f = syncThatAnswers((request) {
      if (request.url.path == '/api/groups/me') {
        return _json({'error': 'no group'}, status: 404);
      }
      return _json([_dog(id: 7, name: '콩이')]);
    });

    expect(await f.sync.load(), isTrue);

    expect(kMyPets.value.map((p) => p.name), ['콩이']);
    expect(f.seen, contains('GET /api/dogs'));
  });

  test('가족 조회가 실패해도 화면이 안 빈다 — 아이 목록이 사라지는 것이 더 나쁘다', () async {
    final f = syncThatAnswers((request) {
      if (request.url.path == '/api/groups/me') {
        return _json({'error': 'boom'}, status: 500);
      }
      return _json([_dog(id: 7, name: '콩이')]);
    });

    expect(await f.sync.load(), isTrue);

    expect(kMyPets.value.map((p) => p.name), ['콩이'],
        reason: '여기서 던지면 가족을 못 읽었다는 이유로 아이가 통째로 사라진다');
  });

  test('옛 서버는 mine 을 안 보낸다 — 그때는 전부 내 아이다', () async {
    final legacy = Map<String, Object?>.from(_dog(id: 1, name: '보리'))..remove('mine');
    final f = syncThatAnswers((request) {
      if (request.url.path == '/api/groups/me') {
        return _json({'error': 'no group'}, status: 404);
      }
      return _json([legacy]);
    });

    await f.sync.load();

    expect(kMyPets.value.single.mine, isTrue,
        reason: '못 읽었다고 고치기를 막으면 자기 아이를 고치던 사람이 이유 없이 막힌다');
  });

  test('아이 편집이 mine 을 안 떨어뜨린다 — 사본 메서드의 실패 모드다', () {
    const borrowed = DogProfile(
        serverId: 1, name: '보리', breed: '푸들', size: DogSize.small,
        ageMonths: 24, mine: false);

    expect(borrowed.copyWith(name: '보리야').mine, isFalse,
        reason: '여기서 빠뜨리면 편집 한 번에 남의 아이가 내 아이로 둔갑한다');
  });
}

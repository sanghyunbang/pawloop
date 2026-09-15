// 서버가 안 뜰 때 홈이 **얼마나** 조용한가 — 이슈 #573.
//
// ## 무엇이 있었나
//
// dev 서버를 끄고 앱을 콜드 스타트했더니 홈이 "아이 목록을 불러오지 못했어요" 를 말하기까지
// 23초가 걸렸다. logcat 으로 잰 것이다.
//
// ```
// 23:05:18.479   GET /api/groups/me     ← 12초 태움
// 23:05:30.127   GET /api/dogs          ← 또 12초 태움
// ```
//
// 원인은 둘이었다.
//
//  1. **한 번이 12초다.** Nielsen 의 응답 시간 한계에서 10초가 "주의를 붙들어 둘 수 있는
//     한계" 라, 12초면 실패가 도착할 때는 이미 사람이 화면을 떠난 뒤다.
//  2. **실패가 두 번 쌓인다.** `PetSync` 는 가족을 묻고, 실패하면 내 아이를 묻는다. 서버에
//     못 닿는 상황이면 두 번째도 같은 이유로 죽으면서 상한을 한 번 더 통째로 태운다.
//
// ## 여기서 지키는 것
//
//  1. 못 닿았으면 **두 번째를 안 묻는다.** 5xx 면 묻는다 — 그건 서버가 살아 있고 그 경로만
//     죽은 것이라 `/api/dogs` 는 될 수 있다.
//  2. 상한은 **한 곳**이 정한다. 저장소마다 숫자를 들면 다음 사람이 그 숫자를 복사한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/core/net/net_timeouts.dart';
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

/// 어떤 경로를 실제로 불렀는지 적어 두는 짝.
({PetSync sync, List<String> seen}) syncThatAnswers(
    Future<http.Response> Function(http.Request request) answer) {
  final seen = <String>[];
  final client = AuthedClient(
    inner: MockClient((request) {
      seen.add(request.url.path);
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
  setUp(() {
    replacePets(const []);
    kPetsLoad.value = PetsLoad.loading;
  });
  tearDown(() {
    replacePets(const []);
    kPetsLoad.value = PetsLoad.loading;
  });

  test('상한은 한 곳이 정하고, 주의 한계(10초) 안쪽이다 (#573)', () {
    expect(NetTimeouts.standard.inSeconds, lessThan(10),
        reason: 'Nielsen 의 10초는 "주의를 붙들어 둘 수 있는 한계" 다 — '
            '그 밖이면 실패가 도착할 때 사람이 이미 떠났다');
    expect(NetTimeouts.standard, FamilyRepository.timeout);
    expect(NetTimeouts.standard, WalkRepository.timeout);
    expect(NetTimeouts.long, greaterThan(NetTimeouts.standard),
        reason: '사진 한 장을 보통 상한에 올리라고 하면 정상 업로드가 실패한다');
  });

  test('못 닿았으면 내 아이를 안 묻는다 — 상한을 두 번 태울 뿐이다 (#573)',
      () async {
    // **시계를 안 돌린다.** 상한이 실제로 몇 초인지는 위 테스트가 상수로 재고, 여기서
    // 잴 것은 "못 닿았을 때 무엇을 하느냐" 다. 진짜로 9초를 기다리면 CI 가 그만큼 길어지고,
    // 상한을 고칠 때마다 이 테스트도 따라 고쳐야 한다.
    final f = syncThatAnswers(
        (request) => Future<http.Response>.error(TimeoutException('못 닿았다')));

    expect(await f.sync.load(), isFalse);

    expect(f.seen, ['/api/groups/me'],
        reason: '/api/dogs 를 또 물으면 같은 이유로 죽으면서 상한을 한 번 더 태운다');
    expect(kPetsLoad.value, PetsLoad.failed);
  });

  test('5xx 면 내 아이를 묻는다 — 서버는 살아 있고 그 경로만 죽었다 (#573)', () async {
    final f = syncThatAnswers((request) async {
      if (request.url.path == '/api/groups/me') {
        return _json({'error': 'boom'}, status: 500);
      }
      return _json([
        {
          'id': 7, 'name': '콩이', 'species': 'dog', 'breed': '믹스견',
          'size': 'small', 'birth': null, 'ageMonths': 30, 'neutered': true,
          'avatarUrl': null, 'mine': true,
        }
      ]);
    });

    expect(await f.sync.load(), isTrue);

    expect(f.seen, contains('/api/dogs'),
        reason: '5xx 는 다른 경로가 살아 있을 수 있다 — 여기서 접으면 볼 수 있는 것을 안 보여 준다');
    expect(kMyPets.value.single.name, '콩이');
  });

  test('가족이 없으면 그대로 내 아이를 묻는다 — 1인 사용자의 화면은 안 바뀐다', () async {
    final f = syncThatAnswers((request) async {
      if (request.url.path == '/api/groups/me') {
        return _json({'error': 'no group'}, status: 404);
      }
      return _json(const []);
    });

    expect(await f.sync.load(), isTrue);
    expect(f.seen, contains('/api/dogs'));
    expect(kPetsLoad.value, PetsLoad.loaded);
  });

  test('못 닿은 것과 5xx 는 다른 종류다 — 문구는 같아도 부르는 쪽이 갈라야 한다 (#573)',
      () async {
    final slow = FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient(
            (_) => Future<http.Response>.error(TimeoutException('못 닿았다'))),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );
    final broken = FamilyRepository(
      baseUrl: _base,
      client: AuthedClient(
        inner: MockClient((_) async => _json({'error': 'boom'}, status: 500)),
        baseUrl: _base,
        store: _Tokens(),
      ),
    );

    final timedOut = await slow.myGroup().then<Object?>((_) => null,
        onError: (Object e) => e);
    final failed =
        await broken.myGroup().then<Object?>((_) => null, onError: (Object e) => e);

    expect((timedOut as FamilyFailure).kind, FamilyFailureKind.timeout);
    expect((failed as FamilyFailure).kind, FamilyFailureKind.network);
    expect(timedOut.message, failed.message,
        reason: '사람이 할 일은 둘 다 "다시 시도" 다 — 갈라야 하는 것은 부르는 쪽이지 문구가 아니다');
  });
}

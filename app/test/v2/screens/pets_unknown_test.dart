// "아이가 없다" 와 "아이 목록을 못 읽었다" 는 **다른 화면**이다 — 이슈 #568.
//
// ## 무엇이 있었나
//
// dev 서버를 끄고 앱을 콜드 스타트했더니 홈이 이랬다.
//
// ```
//        🐾
//   아직 등록된 아이가 없어요
//  등록하면 산책이 기록되기 시작해요
//      우리 아이 등록하기
// ```
//
// 아이는 두 마리 있었다. 목록을 못 읽었을 뿐이다.
//
// **이게 제일 위험한 자리다.** 이 화면이 권하는 대로 등록하면 같은 아이가 두 마리가 되고
// 케어 기록이 둘로 갈린다 — #563 이 막으려고 만든 이슈가 정확히 그것이다. "0회" 를 잘못
// 읽는 것은 오해로 끝나지만, 여기서 잘못 읽으면 **데이터가 망가진다.**
//
// ## 여기서 지키는 것
//
//  1. 못 읽었으면 등록을 **권하지 않는다**. 다시 시도를 준다.
//  2. 정말 한 마리도 없는 사람의 화면은 그대로다 — 그 사람은 등록해야 한다.
//  3. 로그아웃하면 "모른다" 로 돌아간다 — 다음 사람의 첫 화면이 "아직 등록된 아이가
//     없어요" 로 시작하면 안 된다. 그 사람은 아이가 있을 수 있다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/pet_sync.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

class _Repo implements WalkRepository {
  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      const ServerWalkPage(items: [], nextCursor: null, hasMore: false);
  @override
  Future<ServerWalkStats> stats({int? dogId}) async => const ServerWalkStats(
        weekKm: [0, 0, 0, 0, 0, 0, 0], totalKm: 0, walkCount: 0, avgKm: 0,
        allTimeKm: 0, allTimeCount: 0, allTimeMinutes: 0);
  @override
  Future<List<ServerPet>> pets() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

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

/// 가족은 없고, `GET /api/dogs` 가 **두 번째부터 죽는** 서버.
PetSync _syncThatDiesAfterFirstRead() {
  var calls = 0;
  final client = AuthedClient(
    inner: MockClient((request) async {
      if (request.url.path == '/api/groups/me') {
        return http.Response(jsonEncode({'error': 'no group'}), 404,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      calls++;
      if (calls == 1) {
        // 첫 읽기는 성공 — "아이가 없다" 를 서버가 알려 준다.
        return http.Response('[]', 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('boom', 500);
    }),
    baseUrl: 'https://api.example.test',
    store: _Tokens(),
  );
  return PetSync(
    repository: WalkRepository(baseUrl: 'https://api.example.test', client: client),
    family: FamilyRepository(baseUrl: 'https://api.example.test', client: client),
  );
}

Future<void> _pumpHome(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: TodayScreen(feed: WalkFeed(repository: _Repo()))));
  await t.pumpAndSettle();
}

Future<void> _pumpMe(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: MeScreen(feed: WalkFeed(repository: _Repo()))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.signInForTest(const AuthUser(id: 11, nickname: '아빠'));
    replacePets(const []);
    kPetsLoad.value = PetsLoad.failed;
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
    kPetsLoad.value = PetsLoad.failed;
  });

  testWidgets('목록을 못 읽었으면 홈이 등록을 권하지 않는다 (#568)', (t) async {
    await _pumpHome(t);

    expect(find.byKey(const Key('pets-unknown')), findsOneWidget);
    expect(find.text('우리 아이 등록하기'), findsNothing,
        reason: '권하는 대로 등록하면 같은 아이가 두 마리가 된다 — #563 이 막으려던 것이다');
    expect(find.text('아직 등록된 아이가 없어요'), findsNothing);
    expect(find.byKey(const Key('pets-retry')), findsOneWidget);
  });

  testWidgets('정말 한 마리도 없으면 홈이 등록을 권한다 — 그 사람은 등록해야 한다', (t) async {
    // 서버가 빈 목록을 줬다. 빈 목록도 **아는** 답이다.
    replacePets(const []);
    expect(kPetsLoad.value, PetsLoad.loaded, reason: 'replacePets 가 "읽었다" 를 세운다');

    await _pumpHome(t);

    expect(find.text('아직 등록된 아이가 없어요'), findsOneWidget);
    expect(find.text('우리 아이 등록하기'), findsOneWidget);
    expect(find.byKey(const Key('pets-unknown')), findsNothing);
  });

  testWidgets('목록을 못 읽었으면 내 프로필도 등록을 권하지 않는다 (#568)', (t) async {
    await _pumpMe(t);

    final title = t.widget<Text>(find.byKey(const Key('me-empty-title')));
    expect(title.data, '아이 목록을 불러오지 못했어요');
    expect(find.text('우리 아이 등록하기'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('정말 한 마리도 없으면 내 프로필이 등록을 권한다', (t) async {
    replacePets(const []);

    await _pumpMe(t);

    final title = t.widget<Text>(find.byKey(const Key('me-empty-title')));
    expect(title.data, '아직 등록된 아이가 없어요');
    expect(find.text('우리 아이 등록하기'), findsOneWidget);
  });

  testWidgets('아직 읽는 중이면 아무 말도 안 한다 — 셋째 상태 (#568)', (t) async {
    kPetsLoad.value = PetsLoad.loading;

    await _pumpHome(t);

    expect(find.text('아직 등록된 아이가 없어요'), findsNothing,
        reason: '읽어 보지도 않고 "없다" 고 말하면 안 된다');
    expect(find.byKey(const Key('pets-unknown')), findsNothing,
        reason: '읽는 중인 것은 못 읽은 것이 아니다');
    expect(find.byKey(const Key('pets-loading')), findsOneWidget);
  });

  testWidgets('읽는 중이면 내 프로필도 조용하다 (#568)', (t) async {
    kPetsLoad.value = PetsLoad.loading;

    await _pumpMe(t);

    expect(find.byKey(const Key('me-empty-quiet')), findsOneWidget);
    expect(find.byKey(const Key('me-empty-title')), findsNothing);
    expect(find.text('우리 아이 등록하기'), findsNothing);
  });

  test('한 번 읽은 뒤의 실패는 앞 답을 안 뒤집는다 — 없는 사람의 등록 버튼을 빼앗지 않는다 (#568)',
      () async {
    kPetsLoad.value = PetsLoad.loading;
    final sync = _syncThatDiesAfterFirstRead();

    expect(await sync.load(), isTrue);
    expect(kPetsLoad.value, PetsLoad.loaded, reason: '서버가 "아이 없음" 이라고 알려 줬다');

    // 두 번째 읽기는 죽는다. **진짜 PetSync.load 를 부른다** — catch 안의 조건을
    // 테스트가 베껴 쓰면 그 테스트는 코드가 아니라 자기 자신을 잰다.
    expect(await sync.load(), isFalse);

    expect(kPetsLoad.value, PetsLoad.loaded,
        reason: '여기서 failed 로 내리면 정말 아이가 없는 사람이 등록을 못 하게 된다');
  });

  test('처음 읽기가 실패하면 못 읽었다고 말한다 (#568)', () async {
    kPetsLoad.value = PetsLoad.loading;
    final sync = _syncThatDiesAfterFirstRead();
    // 첫 호출을 미리 태워 버려서 이 sync 의 "첫 읽기" 가 실패하게 만든다.
    await sync.load();
    kPetsLoad.value = PetsLoad.loading;

    expect(await sync.load(), isFalse);

    expect(kPetsLoad.value, PetsLoad.failed,
        reason: '콜드 스타트에서 못 읽었으면 등록을 권하면 안 된다');
  });

  testWidgets('게스트에게는 "못 읽었어요" 를 말하지 않는다 — 부른 적이 없다 (#324 · #568)',
      (t) async {
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    kPetsLoad.value = PetsLoad.failed;

    await _pumpHome(t);

    expect(find.byKey(const Key('pets-unknown')), findsNothing,
        reason: '게스트는 목록을 부른 적이 없다. 못 읽은 것이 아니다');
    expect(find.text('아직 등록된 아이가 없어요'), findsOneWidget);
  });

  testWidgets('로그아웃하면 "모른다" 로 돌아간다 — 다음 사람은 아이가 있을 수 있다 (#568)',
      (t) async {
    replacePets(const []);
    expect(kPetsLoad.value, PetsLoad.loaded);

    PetSync.clear();

    expect(kPetsLoad.value, PetsLoad.loading,
        reason: '안 되돌리면 다음 사람의 첫 화면이 "아직 등록된 아이가 없어요" 로 시작한다');
  });
}

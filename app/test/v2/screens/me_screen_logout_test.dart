// 로그아웃을 누르면 **화면이 걷히는가** — 이슈 #513.
//
// 이 화면은 go_router 의 라우트가 아니라 셸 위에 `Navigator.push` 로 얹혀 있다. 그래서
// 라우터가 `AuthState.status` 를 듣고 자기 스택을 `/auth/login` 으로 바꿔도, **그 위에
// 얹힌 화면들이 그것을 덮는다.** 실제로 로그아웃을 눌러도 내 정보 화면이 그대로 남았다.
//
// 탈퇴 화면(`AccountDeleteScreen`)이 같은 결함을 겪고 `popUntil` 로 고쳐 뒀는데, 로그아웃
// 에는 안 들어가 있었다. 여기서는 라우터 없이 **얹힌 것이 걷히는지**만 잰다 — 어디로
// 갈지는 라우터가 정한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';

const _base = 'https://api.example.test';
const _bori = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);

/// 화면이 진짜 서버를 안 부르게. 진짜 저장소는 12초 타이머를 남긴다.
class _Repo implements WalkRepository {
  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: const [], nextCursor: null, hasMore: false);
  @override
  Future<ServerWalkStats> stats({int? dogId}) async => const ServerWalkStats(
      weekKm: [0, 0, 0, 0, 0, 0, 0], totalKm: 0, walkCount: 0, avgKm: 0,
      allTimeKm: 0, allTimeCount: 0, allTimeMinutes: 0);
  @override
  Future<List<ServerPet>> pets() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

class _Tokens implements AuthTokenStore {
  String? access = 'stored';
  String? refresh;
  @override
  Future<String?> readAccessToken() async => access;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    access = accessToken;
    refresh = refreshToken;
  }
  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kMyPets.value = const [_bori];
    kMyDog.value = _bori;
    final store = _Tokens();
    final mock = MockClient((req) async => http.Response('', 204));
    AuthState.configureForTest(
      tokenStore: store,
      repository: AuthRepositoryImpl(
        baseUrl: _base,
        plainClient: mock,
        authedClient: AuthedClient(inner: mock, baseUrl: _base, store: store),
      ),
    );
  });

  tearDown(() {
    AuthState.resetForTest();
    kMyPets.value = const [];
    kMyDog.value = null;
  });

  testWidgets('로그아웃을 누르면 얹힌 내 정보 화면이 걷힌다 — 라우터가 바꿔 둔 화면이 드러나게', (t) async {
    t.view.physicalSize = const Size(1080, 3200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    AuthState.signInForTest(const AuthUser(id: 12, nickname: '나가는사람', provider: 'kakao'));

    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MeScreen(feed: WalkFeed(repository: _Repo())))),
              child: const Text('셸'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('셸'));
    await t.pumpAndSettle();
    expect(find.byType(MeScreen), findsOneWidget);

    await t.ensureVisible(find.text('로그아웃'));
    await t.pumpAndSettle();
    await t.tap(find.text('로그아웃'));
    await t.pumpAndSettle();

    expect(find.byType(MeScreen), findsNothing,
        reason: '남으면 사용자는 로그아웃을 눌렀는데 자기 정보 화면을 계속 본다');
    expect(find.text('셸'), findsOneWidget, reason: '얹힌 것만 걷는다 — 목적지는 라우터가 정한다');
  });
}

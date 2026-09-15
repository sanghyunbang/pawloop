// 홈의 숫자가 **고른 아이의 것**이다 — 이슈 #563.
//
// ## 무엇이 있었나
//
// 산책 조회가 집 기준이 되면서(#563 조각 3) 홈이 이렇게 됐다.
//
// > 뭉치랑 산책 갈까요?  …  이번 주 목표 1/5일 · **3/225분**
//
// | 값 | 어디서 | 무엇의 |
// |:---|:---|:---|
// | 225분 | 뭉치(중형견 45분/일 × 5일) | **한 아이**의 목표 |
// | 3분 | `stats(dogId: null)` | **집 전체** 산책 |
//
// 목표는 아이의 것인데 채우는 숫자는 집 것이었다 — 보리와 걸은 3분이 뭉치의 목표에
// 들어갔다. 그 전에는 둘 다 "내 아이" 라 우연히 맞았다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

const _bori = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small, ageMonths: 24);
const _mungchi = DogProfile(
    serverId: 2, name: '뭉치', breed: '시바', size: DogSize.medium, ageMonths: 48);

/// 어떤 아이로 물었는지를 적어 두는 가짜.
class _Repo implements WalkRepository {
  final List<int?> askedWalks = [];
  final List<int?> askedStats = [];

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async {
    askedWalks.add(dogId);
    return const ServerWalkPage(items: [], nextCursor: null, hasMore: false);
  }

  @override
  Future<ServerWalkStats> stats({int? dogId}) async {
    askedStats.add(dogId);
    return const ServerWalkStats(
        weekKm: [0, 0, 0, 0, 0, 0, 0], totalKm: 0, walkCount: 0, avgKm: 0,
        allTimeKm: 0, allTimeCount: 0, allTimeMinutes: 0);
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(WidgetTester t, _Repo repo) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: TodayScreen(feed: WalkFeed(repository: repo))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.signInForTest(const AuthUser(id: 11, nickname: '아빠'));
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  testWidgets('고른 아이로 통계를 묻는다 — 목표는 이 아이 것인데 숫자가 집 것이면 안 된다 (#563)',
      (t) async {
    replacePets(const [_bori, _mungchi]);
    selectPet(1);
    final repo = _Repo();

    await _pump(t, repo);

    expect(repo.askedStats, [2],
        reason: '아이를 안 실으면 보리와 걸은 분이 뭉치의 주간 목표에 들어간다');
    expect(repo.askedWalks, [2]);
  });

  testWidgets('아이를 바꾸면 다시 묻는다 — 앞 아이의 숫자가 남으면 안 된다 (#563)', (t) async {
    replacePets(const [_bori, _mungchi]);
    selectPet(0);
    final repo = _Repo();
    await _pump(t, repo);

    selectPet(1);
    await t.pumpAndSettle();

    expect(repo.askedStats, [1, 2],
        reason: '히어로는 뭉치인데 숫자는 보리 것인 화면이 된다');
  });

  testWidgets('아이가 없으면 아이 없이 묻는다 — 게스트·첫 실행의 화면은 그대로다', (t) async {
    replacePets(const []);
    final repo = _Repo();

    await _pump(t, repo);

    expect(repo.askedStats, [null]);
  });
}

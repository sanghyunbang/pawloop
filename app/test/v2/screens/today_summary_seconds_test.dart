// 홈의 오늘 요약이 1분이 안 되는 산책을 "0분" 으로 지우던 것 — 이슈 #537.
//
// ## 왜 화면까지 띄우나
//
// `WalkFeedData.today` 가 초를 주는지만 재면, 홈이 예전처럼 `${today.durationS ~/ 60}분` 을
// 그려도 초록이다. 장치와 화면은 따로 되돌려 봐야 한다 — #550 에서 같은 것을 놓쳤다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

class _Repo implements WalkRepository {
  _Repo(this.items);

  final List<ServerWalk> items;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: items, nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: const [0, 0, 0, 0, 0, 0, 0],
        totalKm: 0.7,
        walkCount: 1,
        avgKm: 0.7,
        allTimeKm: 0.7,
        allTimeCount: 1,
        // 요약 카드의 값과 겹치지 않는 수 — 겹치면 find.text 가 둘을 찾는다.
        allTimeMinutes: 99,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalk _walkToday(int durationS) {
  final now = DateTime.now();
  return ServerWalk(
    id: 14,
    dogId: 1,
    dogIds: const [1],
    clientWalkId: 'ck-14',
    startedAt: DateTime(now.year, now.month, now.day, 8, 30),
    distanceM: 704,
    durationS: durationS,
  );
}

Future<void> _pump(WidgetTester t, int durationS) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    home: TodayScreen(feed: WalkFeed(repository: _Repo([_walkToday(durationS)]))),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kMyDog.value = null;
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(AuthState.resetForTest);

  testWidgets('44초짜리 산책이 홈에서 "44초" 다 — 예전에는 "0분" 이었다 (#537)', (t) async {
    await _pump(t, 44);

    expect(find.text('44초'), findsOneWidget);
    expect(find.text('0분'), findsNothing,
        reason: '거리는 0.7km 인데 시간이 0분이면 오늘 걸은 사실이 화면에서 사라진다');
  });

  testWidgets('1분이 넘으면 지금처럼 분이다', (t) async {
    await _pump(t, 720);

    expect(find.text('12분'), findsOneWidget);
  });
}

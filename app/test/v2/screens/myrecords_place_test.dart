// 산책에 적은 장소를 기록에서 다시 볼 수 있다 — 이슈 #547.
//
// ## 무엇이 있었나
//
// 기록하기 화면이 "어디를 걸었나요?" 를 묻고 저장까지 했는데, 그 뒤로 그 이름을 볼 수 있는
// 자리가 없었다 — 목록도 상세도 날짜 · 거리 · 시간 · 메모뿐이었다. 통계의 "자주 가는 곳" 에만
// 쌓였다.
//
// 데이터는 화면까지 와 있었다. 계약의 `Walk.place` 가 있고 `ServerWalk.tryParse` 도 읽는다.
// `_RecordView` 에 축이 없어서 안 그렸을 뿐인데, 그 자리의 주석은 **"계약의 Walk 에 장소가
// 없어서다"** 라고 낡은 말을 하고 있었다 — 다음 사람에게 "못 한다" 고 잘못 알려 주는 문장이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';
import 'package:heat_trip_flutter/v2/screens/walk_detail_screen.dart';

class _Repo implements WalkRepository {
  _Repo({this.items = const []});

  List<ServerWalk> items;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: items, nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: const [0, 0, 0, 0, 0, 0, 0],
        totalKm: 0,
        walkCount: 0,
        avgKm: 0,
        allTimeKm: 0.7,
        allTimeCount: items.length,
        allTimeMinutes: 12,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalk _walk({WalkPlaceRef? place}) => ServerWalk(
      id: 14,
      dogId: 1,
      dogIds: const [1],
      clientWalkId: 'ck-14',
      startedAt: DateTime(2026, 9, 15, 8, 38),
      distanceM: 704,
      durationS: 720,
      place: place,
    );

Future<void> _pump(WidgetTester t, ServerWalk walk) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _Repo(items: [walk]);
  await t.pumpWidget(MaterialApp(
    home: MyRecordsScreen(feed: WalkFeed(repository: repo), repository: repo),
  ));
  await t.pumpAndSettle();
}

void main() {
  // 초안 큐가 기기 저장소를 읽는다 — 목을 안 깔면 그 읽기가 던져 목록이 "못 불러왔어요" 가 된다.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('카탈로그에서 고른 곳이 카드에 보인다 (#547)', (t) async {
    await _pump(
        t,
        _walk(
            place: const WalkPlaceRef(
                title: '서울숲', source: 'kto', contentId: '128611')));

    expect(find.text('서울숲'), findsOneWidget,
        reason: '저장할 때 적은 것을 다시 볼 수 없으면, 적은 사람에게는 어디로 갔는지 모르는 값이 된다');
  });

  testWidgets('직접 적은 이름도 보인다 — "자주 가는 곳" 에는 안 쌓여도 이 기록에는 남는다', (t) async {
    await _pump(t, _walk(place: const WalkPlaceRef(title: '동네 한 바퀴')));

    expect(find.text('동네 한 바퀴'), findsOneWidget);
  });

  testWidgets('장소가 없으면 그 줄에 아무것도 안 붙는다', (t) async {
    await _pump(t, _walk());

    expect(find.byIcon(Icons.place_outlined), findsNothing,
        reason: '빈 자리표시가 생기면 장소를 안 적은 기록이 뭔가 빠진 것처럼 보인다');
  });

  testWidgets('카드를 누르면 상세에도 그 이름이 있다', (t) async {
    await _pump(
        t,
        _walk(
            place: const WalkPlaceRef(
                title: '서울숲', source: 'kto', contentId: '128611')));

    await t.tap(find.text('아침 산책'));
    await t.pumpAndSettle();

    expect(find.byType(WalkDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('detail-place')), findsOneWidget);
    expect(find.text('서울숲'), findsOneWidget);
  });

  testWidgets('긴 이름은 말줄임으로 줄어든다 — 날짜를 밀어내지 않는다', (t) async {
    await _pump(
        t,
        _walk(
            place: const WalkPlaceRef(
                title: '서울특별시 성동구 서울숲 제이홉숲 벤치정원 앞 산책로 입구')));

    expect(t.takeException(), isNull, reason: '390dp 에서 넘치면 안 된다');
    final place = find.byKey(const Key('record-place-ck-14'));
    expect(place, findsOneWidget);
    expect(t.widget<Text>(place).overflow, TextOverflow.ellipsis);
  });
}

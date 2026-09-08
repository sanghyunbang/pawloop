// 기록 카드에서 공유하기 — 이슈 #344 완료 조건 1 의 뒷쪽.
//
// ## 여기서 재는 것
//
//  1. **길이 있는가.** 종료 시트에서만 공유되면, 산책이 끝나고 몇 분 뒤에 "아 아까 그거
//     올릴걸" 하는 순간에는 방법이 없다. 이슈가 기록 카드에도 같은 버튼을 요구한다.
//
//  2. **서버가 준 기록에는 선이 없다.** A안(#235)에서 경로는 기기 밖으로 안 나가므로
//     목록에서 만든 카드는 숫자만 있는 한 장이다. 여기서 선이 생기면 그건 좌표가
//     서버를 다녀왔다는 뜻이다.
//
//  3. **아이가 없으면 안 만든다.** 카드의 첫 줄이 아이 이름이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share.dart';
import 'package:heat_trip_flutter/v2/walk/walk_share_card.dart';

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
        allTimeKm: 2.4,
        allTimeCount: items.length,
        allTimeMinutes: 30,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalk _walk() => ServerWalk(
      id: 7,
      dogId: 1,
      clientWalkId: 'ck-7',
      startedAt: DateTime(2026, 9, 1, 9, 5),
      distanceM: 2400,
      durationS: 1800,
    );

const _bori = DogProfile(name: '보리', breed: '말티즈', size: DogSize.small, ageMonths: 24);

Future<void> _openShare(WidgetTester t, {required Future<void> Function(WalkShareCard) share}) async {
  final repo = _Repo(items: [_walk()]);
  await t.pumpWidget(MaterialApp(
    home: MyRecordsScreen(feed: WalkFeed(repository: repo), repository: repo, share: share),
  ));
  await t.pumpAndSettle();

  await t.tap(find.byIcon(Icons.more_horiz_rounded));
  await t.pumpAndSettle();
  expect(find.text('공유하기'), findsOneWidget, reason: '기록 카드에도 같은 버튼이 있어야 한다');
  await t.tap(find.text('공유하기'));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kMyDog.value = _bori;
  });
  tearDown(() {
    walkFeedRevision.value = 0;
    kMyDog.value = null;
  });

  testWidgets('… → 공유하기 → 그 기록의 숫자로 카드를 만든다', (t) async {
    WalkShareCard? made;
    await _openShare(t, share: (c) async => made = c);

    expect(made, isNotNull, reason: '공유하기를 눌렀는데 카드가 안 만들어졌다');
    expect(made!.dogName, '보리');
    expect(made!.distanceLabel, '2.4km');
    expect(made!.timeLabel, '30분');
    expect(made!.dateLabel, contains('09:05'));
  });

  testWidgets('목록에서 만든 카드에는 선이 없다 — 서버는 좌표를 안 준다(A안 #235)', (t) async {
    WalkShareCard? made;
    await _openShare(t, share: (c) async => made = c);

    expect(made!.lngLat, isNull);
    expect(made!.hasRoute, isFalse,
        reason: '여기서 선이 생기면 좌표가 서버를 다녀왔다는 뜻이다');
  });

  testWidgets('시트가 미리 말한다 — 눌러 보고 알게 하지 않는다', (t) async {
    final repo = _Repo(items: [_walk()]);
    await t.pumpWidget(MaterialApp(
      home: MyRecordsScreen(feed: WalkFeed(repository: repo), repository: repo),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_horiz_rounded));
    await t.pumpAndSettle();

    expect(find.text('숫자만 담긴 카드 한 장'), findsOneWidget);
  });

  testWidgets('아이가 없으면 카드를 안 만들고 등록을 안내한다', (t) async {
    kMyDog.value = null;
    var called = false;
    await _openShare(t, share: (_) async => called = true);

    expect(called, isFalse, reason: '이름 없는 카드를 만들면 첫 줄이 빈다');
    expect(find.text('아이를 먼저 등록해 주세요'), findsOneWidget);
  });

  testWidgets('공유가 실패하면 문구를 띄운다 — 조용히 삼키지 않는다', (t) async {
    await _openShare(t, share: (_) async => throw const WalkShareException('없음'));

    expect(find.text('공유 시트를 열지 못했어요'), findsOneWidget);
  });
}

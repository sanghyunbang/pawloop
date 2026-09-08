// 기록 카드가 함께 나간 아이들을 말한다 — 이슈 #343.
//
// ## 여기서 재는 것
//
//  1. **두 마리 이상일 때만 적는다.** 한 마리인 사람에게 매 카드마다 자기 아이 이름을
//     한 번 더 보여 줄 이유가 없다.
//  2. **이름을 못 찾은 id 는 조용히 뺀다.** 지운 아이의 산책은 계속 세지만(#156) 그
//     아이의 이름은 더 이상 없다 — 거기에 "알 수 없음" 을 적으면 사용자는 자기가 뭘
//     잘못한 줄 안다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';

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

ServerWalk _walk({List<int> dogIds = const [1]}) => ServerWalk(
      id: 7,
      dogId: 1,
      dogIds: dogIds,
      clientWalkId: 'ck-7',
      startedAt: DateTime(2026, 9, 1, 9, 5),
      distanceM: 2400,
      durationS: 1800,
    );

DogProfile _dog(String name, int serverId) => DogProfile(
      serverId: serverId,
      name: name,
      breed: '말티즈',
      size: DogSize.small,
      ageMonths: 24,
    );

Future<void> _pump(WidgetTester t, ServerWalk walk) async {
  final repo = _Repo(items: [walk]);
  await t.pumpWidget(MaterialApp(
    home: MyRecordsScreen(feed: WalkFeed(repository: repo), repository: repo),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kMyPets.value = [_dog('보리', 1), _dog('초코', 2)];
  });
  tearDown(() {
    walkFeedRevision.value = 0;
    kMyPets.value = const [];
  });

  testWidgets('두 마리와 걸었으면 카드에 둘 다 적힌다', (t) async {
    await _pump(t, _walk(dogIds: const [1, 2]));

    expect(find.text('보리 · 초코'), findsOneWidget);
  });

  testWidgets('한 마리면 적지 않는다 — 매 카드에 자기 아이 이름을 또 볼 이유가 없다', (t) async {
    await _pump(t, _walk(dogIds: const [1]));

    expect(find.textContaining('보리'), findsNothing);
  });

  testWidgets('이름을 못 찾은 아이가 섞이면 남는 하나로는 적지 않는다', (t) async {
    // 2번 아이를 지웠다 — 산책은 남지만 이름은 없다(#156).
    kMyPets.value = [_dog('보리', 1)];

    await _pump(t, _walk(dogIds: const [1, 2]));

    expect(find.textContaining('알 수 없음'), findsNothing);
    expect(find.text('보리'), findsNothing, reason: '한 마리만 적으면 함께 나간 사실이 사라진다');
  });
}

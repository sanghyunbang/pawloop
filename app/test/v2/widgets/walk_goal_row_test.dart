// 홈의 주간 목표 한 줄 — 이슈 #341.
//
// 이 줄은 **없어야 할 때 없는 것**이 절반이다. 고양이에게 산책 목표를 제안하면 근거 없는
// 숫자이고, 연속이 끊긴 사람에게 "0일" 을 보여 주면 그건 혼내는 말이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_goal_store.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/domain/walk_goal.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_goal_row.dart';

final _today = DateTime(2026, 9, 7); // 월요일

const _bori = DogProfile(
  serverId: 3,
  name: 'Bori',
  breed: '말티즈',
  size: DogSize.medium,
  ageMonths: 0,
);

ServerWalk _walk(int day, {int minutes = 20}) => ServerWalk(
      id: day,
      dogId: 3,
      clientWalkId: 'ck-$day',
      startedAt: DateTime(2026, 9, day, 19),
      distanceM: 1200,
      durationS: minutes * 60,
    );

WalkFeedData _feed({
  List<double> weekKm = const [0, 0, 0, 0, 0, 0, 0],
  List<int> weekMinutes = const [0, 0, 0, 0, 0, 0, 0],
  List<ServerWalk> walks = const [],
}) =>
    WalkFeedData(
      walks: walks,
      pending: const [],
      stats: ServerWalkStats(
        weekKm: weekKm,
        weekMinutes: weekMinutes,
        totalKm: 0,
        walkCount: walks.length,
        avgKm: 0,
        allTimeKm: 0,
        allTimeCount: 0,
        allTimeMinutes: 0,
      ),
      offline: false,
    );

Future<void> _pump(
  WidgetTester tester, {
  DogProfile? dog = _bori,
  required WalkFeedData data,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WalkGoalRow(dog: dog, data: data, now: _today),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('세운 목표가 없으면 크기로 제안한 값으로 그린다 — 중형견 주 5일 225분', (tester) async {
    await _pump(
      tester,
      data: _feed(
        weekKm: const [1.2, 0, 1.4, 0, 0, 0, 0],
        weekMinutes: const [20, 0, 22, 0, 0, 0, 0],
      ),
    );

    expect(find.text('2/5일 · 42/225분'), findsOneWidget);
  });

  testWidgets('세워 둔 목표가 있으면 그것으로 그린다', (tester) async {
    await const WalkGoalStore()
        .save(const WalkGoal(daysPerWeek: 5, minutesPerWeek: 90), petId: 3);

    await _pump(
      tester,
      data: _feed(
        weekKm: const [1.2, 0, 1.4, 0, 0, 0, 0],
        weekMinutes: const [20, 0, 22, 0, 0, 0, 0],
      ),
    );

    expect(find.text('2/5일 · 42/90분'), findsOneWidget);
  });

  testWidgets('개가 아니면 줄 자체가 없다 — 산책 권장량은 개에 대한 자료다', (tester) async {
    await _pump(
      tester,
      dog: const DogProfile(
        serverId: 4,
        name: '나비',
        breed: '코숏',
        species: PetSpecies.cat,
        size: DogSize.small,
        ageMonths: 0,
      ),
      data: _feed(),
    );

    expect(find.textContaining('일 · '), findsNothing);
  });

  testWidgets('아이가 없으면 줄 자체가 없다', (tester) async {
    await _pump(tester, dog: null, data: _feed());

    expect(find.textContaining('이번 주 목표'), findsNothing);
  });

  testWidgets('이어 걸었으면 며칠째인지 붙는다', (tester) async {
    await _pump(
      tester,
      data: _feed(
        weekKm: const [1.2, 0, 0, 0, 0, 0, 0],
        weekMinutes: const [20, 0, 0, 0, 0, 0, 0],
        // 5·6·7일 — 오늘까지 사흘 연속.
        walks: [_walk(5), _walk(6), _walk(7)],
      ),
    );

    expect(find.text('3일째'), findsOneWidget);
  });

  testWidgets('끊겼으면 그 자리를 비운다 — "0일" 은 혼내는 말이다', (tester) async {
    await _pump(
      tester,
      data: _feed(
        weekKm: const [1.2, 0, 0, 0, 0, 0, 0],
        weekMinutes: const [20, 0, 0, 0, 0, 0, 0],
        walks: [_walk(3)],
      ),
    );

    expect(find.textContaining('일째'), findsNothing);
  });

  testWidgets('눌러서 고치면 그 값이 저장되고 줄이 다시 그려진다', (tester) async {
    await _pump(
      tester,
      data: _feed(
        weekKm: const [1.2, 0, 0, 0, 0, 0, 0],
        weekMinutes: const [30, 0, 0, 0, 0, 0, 0],
      ),
    );
    expect(find.text('1/5일 · 30/225분'), findsOneWidget);

    await tester.tap(find.text('이번 주 목표'));
    await tester.pumpAndSettle();

    expect(find.textContaining('참고'), findsOneWidget,
        reason: '수의사의 지시가 아니라는 말이 고치는 자리에도 있어야 한다');

    // 주 4일로 한 번 줄이고 저장한다.
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 목표로 할게요'));
    await tester.pumpAndSettle();

    expect(await const WalkGoalStore().read(petId: 3),
        const WalkGoal(daysPerWeek: 4, minutesPerWeek: 225));
    expect(find.text('1/4일 · 30/225분'), findsOneWidget,
        reason: '저장만 하고 화면이 안 바뀌면 사용자는 안 눌린 줄 안다');
  });
}

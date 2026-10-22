// 홈 카드가 **그 집 목록대로** 그린다 — 이슈 #560 조각 4.
//
// ## 왜 이 파일이 따로 필요했나
//
// 카드를 항목 기준으로 바꿨는데 기존 위젯 테스트 스물몇 개가 **한 번에 전부 초록**이었다.
// 그럴 리가 없어서 보니, 그 목들이 어떤 GET 에나 케어 로그 배열을 돌려주는 바람에 항목
// 목록이 빈 것으로 읽히고 **대비책(기본 일곱)** 으로 그려지고 있었다. 즉 옛 테스트는
// 새 경로를 한 줄도 안 지난다.
//
// 여기는 항목 목록을 **진짜로 돌려주는** 목을 쓴다. 그래야 "목록대로 그린다" 가 재어진다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/family_repository.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart' show RootTab;
import 'package:heat_trip_flutter/v2/widgets/today_care_card.dart';

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

Map<String, Object?> _item({
  required int id,
  required String name,
  String icon = 'etc',
  String? systemType,
  int? dailyTarget,
  int sortOrder = 0,
  String? archivedAt,
}) =>
    {
      'id': id,
      'dogId': null,
      'name': name,
      'icon': icon,
      'systemType': systemType,
      'dailyTarget': dailyTarget,
      'sortOrder': sortOrder,
      'archivedAt': archivedAt,
    };

Map<String, Object?> _log({
  required int id,
  String? type,
  int? careItemId,
  String who = '엄마',
  String at = '2026-09-16T10:39:00',
}) =>
    {
      'id': id,
      'dogId': null,
      'groupId': 3,
      'careItemId': careItemId,
      'type': type,
      'doneBy': {'userId': 11, 'nickname': who},
      'occurredAt': at,
      'memo': null,
    };

({FamilyRepository repo, List<String> posts}) fixture({
  required List<Map<String, Object?>> items,
  List<Map<String, Object?>> logs = const [],
  int itemsStatus = 200,
}) {
  final posts = <String>[];
  final repo = FamilyRepository(
    baseUrl: _base,
    client: AuthedClient(
      inner: MockClient((request) async {
        if (request.url.path == '/api/groups/me') {
          return _json({'id': 3, 'name': '보리네', 'roomId': 9, 'members': []});
        }
        if (request.method == 'POST') {
          posts.add(request.body);
          return _json(_log(id: 99, careItemId: 9), status: 201);
        }
        if (request.url.path.endsWith('/care-items')) {
          return itemsStatus >= 400
              ? _json({'message': '안 됨'}, status: itemsStatus)
              : _json(items);
        }
        return _json(logs);
      }),
      baseUrl: _base,
      store: _Tokens(),
    ),
  );
  return (repo: repo, posts: posts);
}

Future<void> _pump(WidgetTester t, FamilyRepository repo,
    {double textScale = 1.0}) async {
  // **진짜 기기 폭으로 잰다** — 1080dp 로 재면 칸이 250dp 씩이라 아무것도 안 넘친다.
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
          body: SingleChildScrollView(child: TodayCareCard(repository: repo))),
    ),
  ));
  await t.pumpAndSettle();
}

/// 기본 일곱과 같은 모양의 목록에 "양치" 하나를 더한 집.
List<Map<String, Object?>> _eight() => [
      _item(id: 1, name: '물', icon: 'water', systemType: 'water', sortOrder: 0),
      _item(id: 2, name: '밥', icon: 'meal', systemType: 'meal', sortOrder: 1),
      _item(id: 3, name: '산책', icon: 'walk', systemType: 'walk', sortOrder: 2),
      _item(id: 4, name: '투약', icon: 'med', systemType: 'med', sortOrder: 3),
      _item(id: 5, name: '병원', icon: 'vet', systemType: 'vet', sortOrder: 4),
      _item(id: 6, name: '배변', icon: 'poop', systemType: 'poop', sortOrder: 5),
      _item(id: 7, name: '마킹', icon: 'pee', systemType: 'pee', sortOrder: 6),
      _item(id: 9, name: '양치', icon: 'tooth', sortOrder: 7),
    ];

void main() {
  testWidgets('직접 만든 항목이 칸으로 생긴다 — 만들었는데 카드에 없으면 만든 뜻이 없다', (t) async {
    final f = fixture(items: _eight());
    await _pump(t, f.repo);

    expect(find.byKey(const Key('care-cell-item-9')), findsOneWidget);
    expect(find.text('양치'), findsOneWidget);
  });

  testWidgets('이름을 고치면 카드도 그 이름이다 — 이름은 기록이 아니라 목록에 있다', (t) async {
    final f = fixture(items: [
      _item(id: 2, name: '아침밥', icon: 'meal', systemType: 'meal', sortOrder: 0),
    ]);
    await _pump(t, f.repo);

    expect(find.text('아침밥'), findsOneWidget);
    expect(find.text('밥'), findsNothing);
  });

  testWidgets('접힌 항목은 카드에 안 뜬다 — 그게 접기의 뜻이다', (t) async {
    final f = fixture(items: [
      _item(id: 1, name: '물', icon: 'water', systemType: 'water', sortOrder: 0),
      _item(
          id: 4,
          name: '투약',
          icon: 'med',
          systemType: 'med',
          sortOrder: 1,
          archivedAt: '2026-09-16T03:00:00Z'),
    ]);
    await _pump(t, f.repo);

    expect(find.byKey(const Key('care-cell-water')), findsOneWidget);
    expect(find.byKey(const Key('care-cell-med')), findsNothing);
  });

  testWidgets('직접 만든 칸을 누르면 종류가 아니라 항목 번호를 보낸다', (t) async {
    final f = fixture(items: _eight());
    await _pump(t, f.repo);

    await t.tap(find.byKey(const Key('care-cell-item-9')));
    await t.pumpAndSettle();

    final sent = jsonDecode(f.posts.single) as Map<String, dynamic>;
    expect(sent['careItemId'], 9);
    expect(sent.containsKey('type'), isFalse,
        reason: '계약이 "정확히 하나" 라 둘 다 보내면 서버가 400 이다');
  });

  testWidgets('기본 칸은 종류를 보낸다 — 서버가 항목까지 붙여 옛 집계가 그대로 돈다', (t) async {
    final f = fixture(items: _eight());
    await _pump(t, f.repo);

    await t.tap(find.byKey(const Key('care-cell-meal')));
    await t.pumpAndSettle();

    final sent = jsonDecode(f.posts.single) as Map<String, dynamic>;
    expect(sent['type'], 'meal');
    expect(sent.containsKey('careItemId'), isFalse);
  });

  testWidgets('직접 만든 항목의 기록이 그 칸에 세어진다 — 서버가 푼 careItemId 로 붙는다',
      (t) async {
    final f = fixture(items: _eight(), logs: [
      _log(id: 1, careItemId: 9),
      _log(id: 2, careItemId: 9, who: '아빠', at: '2026-09-16T11:00:00'),
    ]);
    await _pump(t, f.repo);

    expect(
        (t.widget<Text>(find.byKey(const Key('care-line1-item-9')))).data, '2회');
  });

  testWidgets('하루 목표가 있으면 1/2 로 그린다 — 두 번 줘야 하는 집에서 1회는 끝난 게 아니다',
      (t) async {
    final f = fixture(
      items: [
        _item(
            id: 2, name: '밥', icon: 'meal', systemType: 'meal', dailyTarget: 2),
      ],
      logs: [_log(id: 1, type: 'meal', careItemId: 2)],
    );
    await _pump(t, f.repo);

    expect((t.widget<Text>(find.byKey(const Key('care-line1-meal')))).data, '1/2');
  });

  testWidgets('목표가 있고 아직 안 했으면 0/2 다 — "아직" 보다 무엇이 남았는지가 보인다',
      (t) async {
    final f = fixture(items: [
      _item(id: 2, name: '밥', icon: 'meal', systemType: 'meal', dailyTarget: 2),
    ]);
    await _pump(t, f.repo);

    expect((t.widget<Text>(find.byKey(const Key('care-line1-meal')))).data, '0/2');
  });

  testWidgets('칸이 둘이면 한 줄에 둘이다 — 넷으로 고정하면 빈 자리가 폭을 먹는다', (t) async {
    final f = fixture(items: [
      _item(id: 1, name: '물', icon: 'water', systemType: 'water', sortOrder: 0),
      _item(id: 2, name: '밥', icon: 'meal', systemType: 'meal', sortOrder: 1),
    ]);
    await _pump(t, f.repo);

    final water = t.getSize(find.byKey(const Key('care-cell-water')));
    final meal = t.getSize(find.byKey(const Key('care-cell-meal')));
    expect(water.width, meal.width, reason: '칸 크기는 언제나 같다(#561)');
    expect(water.width, greaterThan(120),
        reason: '넷으로 고정했다면 390dp 에서 90dp 언저리다 — 둘이면 더 넓어야 한다');
  });

  testWidgets('칸이 여덟이어도 한 줄은 넷까지다 — 다섯은 라벨이 잘린다(#326)', (t) async {
    final f = fixture(items: _eight());
    await _pump(t, f.repo);

    // **폭이 아니라 줄을 잰다.** 처음에 "칸 폭이 110 보다 좁다" 로 뒀더니, 여덟을 한 줄에
    // 다 넣는 변형이 칸을 44dp 로 만들면서 그 단언을 **그대로 통과**했다(실측) — 한쪽
    // 방향만 막는 가드였다. y 좌표로 줄을 세면 많아도 적어도 잡힌다.
    double top(String slug) => t.getTopLeft(find.byKey(Key('care-cell-$slug'))).dy;

    expect({top('water'), top('meal'), top('walk'), top('med')}, hasLength(1),
        reason: '앞의 넷은 한 줄이다');
    expect(top('vet'), greaterThan(top('water')),
        reason: '다섯째는 다음 줄이다 — 한 줄에 다섯이면 390dp 에서 라벨이 잘린다(#326)');
    expect({top('vet'), top('poop'), top('pee'), top('item-9')}, hasLength(1),
        reason: '둘째 줄도 넷이다');

    expect(t.getSize(find.byKey(const Key('care-cell-water'))).width,
        t.getSize(find.byKey(const Key('care-cell-item-9'))).width,
        reason: '줄이 달라도 칸 폭은 같다(#561)');
  });

  testWidgets('칸 여덟이 전부 같은 높이다 — 가변 개수에서도 #561 은 그대로다', (t) async {
    final f = fixture(items: _eight(), logs: [
      _log(id: 1, type: 'water', careItemId: 1),
      _log(id: 2, careItemId: 9),
      _log(id: 3, type: 'med', careItemId: 4, who: '아빠'),
    ]);
    await _pump(t, f.repo);

    final slugs = ['water', 'meal', 'walk', 'med', 'vet', 'poop', 'pee', 'item-9'];
    final heights =
        slugs.map((s) => t.getSize(find.byKey(Key('care-cell-$s'))).height).toList();

    expect(heights.toSet(), hasLength(1), reason: '실측: $heights');
  });

  testWidgets('목록을 못 읽으면 기본 일곱으로 그린다 — 카드가 통째로 비면 기능이 사라진 것처럼 보인다',
      (t) async {
    final f = fixture(items: const [], itemsStatus: 500, logs: [
      _log(id: 1, type: 'meal'),
    ]);
    await _pump(t, f.repo);

    expect(find.byKey(const Key('care-cell-meal')), findsOneWidget);
    expect(find.byKey(const Key('care-cell-pee')), findsOneWidget);
    expect((t.widget<Text>(find.byKey(const Key('care-line1-meal')))).data, '엄마',
        reason: 'careItemId 가 없는 옛 기록도 종류로 제 칸에 붙어야 한다');

    // 일곱이면 4 + 3 이라 마지막 줄에 빈 자리가 하나 남는다. 그 자리를 비워 두지 않으면
    // 둘째 줄 칸이 첫째 줄보다 넓어져 같은 카드가 두 벌처럼 보인다.
    expect(t.getSize(find.byKey(const Key('care-cell-vet'))).width,
        t.getSize(find.byKey(const Key('care-cell-water'))).width,
        reason: '마지막 줄의 빈 자리를 비워 둬야 줄마다 칸 폭이 같다');
  });
  testWidgets('"오늘 한 일" 이 칸 이름을 적는다 — 직접 만든 항목이 "케어" 로 뭉개지면 안 된다',
      (t) async {
    // **에뮬레이터에서 찾은 것이다.** 종류에서 이름을 뽑고 있어서, 직접 만든 항목의 줄이
    // `케어` 로 적혔다 — 그 줄에서 알려 주는 것이 "무엇을 했나" 하나인데 그것만 빠졌다.
    final f = fixture(items: _eight(), logs: [
      _log(id: 1, careItemId: 9),
      _log(id: 2, type: 'meal', careItemId: 2, who: '아빠'),
    ]);
    await _pump(t, f.repo);

    expect(find.descendant(
      of: find.byKey(const Key('care-log-1')),
      matching: find.text('양치'),
    ), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const Key('care-log-2')),
      matching: find.text('밥'),
    ), findsOneWidget, reason: '기본 항목도 이름은 그 집이 적은 것이다');
    expect(find.text('케어'), findsNothing);
  });
  group('주변 찾기 — 기본 배지에만 붙는다 (2026-09-16)', () {
    testWidgets('병원·밥·산책이 있으면 세 갈래가 뜬다 — 물·배변·마킹은 갈 곳이 없다', (t) async {
      final f = fixture(items: _eight());
      await _pump(t, f.repo);

      expect(find.byKey(const Key('care-nearby-vet')), findsOneWidget);
      expect(find.byKey(const Key('care-nearby-shop')), findsOneWidget);
      expect(find.byKey(const Key('care-nearby-trail')), findsOneWidget);
      expect(find.text('동물병원'), findsOneWidget);
    });

    testWidgets('병원과 투약이 함께 있어도 칩은 하나다 — 같은 곳으로 간다', (t) async {
      final f = fixture(items: [
        _item(id: 4, name: '투약', icon: 'med', systemType: 'med', sortOrder: 0),
        _item(id: 5, name: '병원', icon: 'vet', systemType: 'vet', sortOrder: 1),
      ]);
      await _pump(t, f.repo);

      expect(find.byKey(const Key('care-nearby-vet')), findsOneWidget);
    });

    testWidgets('직접 만든 항목에는 안 붙는다 — 단순 투두다', (t) async {
      final f = fixture(items: [
        _item(id: 9, name: '양치', icon: 'tooth', sortOrder: 0),
      ]);
      await _pump(t, f.repo);

      expect(find.text('주변'), findsNothing,
          reason: '갈 곳이 없으면 줄 자체가 없어야 한다 — 눌러 보고 실망하게 두지 않는다');
    });

    testWidgets('접은 칸은 주변에서도 사라진다', (t) async {
      final f = fixture(items: [
        _item(id: 2, name: '밥', icon: 'meal', systemType: 'meal', sortOrder: 0),
        _item(
            id: 5,
            name: '병원',
            icon: 'vet',
            systemType: 'vet',
            sortOrder: 1,
            archivedAt: '2026-09-16T03:00:00Z'),
      ]);
      await _pump(t, f.repo);

      expect(find.byKey(const Key('care-nearby-shop')), findsOneWidget);
      expect(find.byKey(const Key('care-nearby-vet')), findsNothing);
    });

    testWidgets('누르면 지도 탭을 그 갈래로 부탁한다 — 화면을 직접 밀지 않는다', (t) async {
      RootTab.index.value = 0;
      RootTab.exploreCategory.value = null;
      addTearDown(() {
        RootTab.index.value = 0;
        RootTab.exploreCategory.value = null;
      });
      final f = fixture(items: _eight());
      await _pump(t, f.repo);

      await t.tap(find.byKey(const Key('care-nearby-trail')));
      await t.pump();

      expect(RootTab.exploreCategory.value, 'trail');
      expect(RootTab.index.value, 1,
          reason: '화면을 직접 밀면 탭 바 없는 지도가 열려 돌아올 길이 없다');
    });
  });
}

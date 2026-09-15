// 남이 등록한 아이는 **고치기 자리를 안 연다** — 이슈 #563.
//
// ## 무엇이 있었나
//
// 가족이 아이를 함께 돌보기 시작하면서 내 프로필의 아이 목록에 **남이 등록한 아이가**
// 올 수 있게 됐다. "우리 아이 정보 관리" 를 그대로 두면 눌렀을 때 편집 화면까지 갔다가
// **저장에서 404** 를 만난다 — 누르기 전에 말해 주는 편이 낫다.
//
// 숨기지 않고 이유를 적는 이유는, 아이를 바꿀 때마다 메뉴 항목이 나타났다 사라지면 화면이
// 흔들리고 "왜 없지" 를 묻게 되기 때문이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';

/// 서버를 안 타는 가짜 — 이 테스트가 보는 것은 메뉴 배너뿐이다.
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

const _mine = DogProfile(
    serverId: 2, name: '뭉치', breed: '시바', size: DogSize.medium, ageMonths: 48);
const _borrowed = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small,
    ageMonths: 24, mine: false);

Future<void> _pump(WidgetTester t) async {
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
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  testWidgets('내가 등록한 아이면 "우리 아이 정보 관리" 가 그대로 있다', (t) async {
    replacePets(const [_mine]);
    selectPet(0);

    await _pump(t);

    expect(find.text('우리 아이 정보 관리'), findsOneWidget);
    expect(find.byKey(const Key('not-my-dog-banner')), findsNothing);
  });

  testWidgets('남이 등록한 아이면 고치기 대신 이유를 말한다 (#563)', (t) async {
    replacePets(const [_borrowed]);
    selectPet(0);

    await _pump(t);

    expect(find.text('우리 아이 정보 관리'), findsNothing,
        reason: '누르면 편집 화면까지 갔다가 저장에서 404 다 — 누르기 전에 말해 준다');
    expect(find.byKey(const Key('not-my-dog-banner')), findsOneWidget);
    expect(find.text('보리는 가족이 등록한 아이예요'), findsOneWidget);
    expect(find.text('같이 돌볼 수 있어요. 정보 수정은 등록한 사람이 해요'), findsOneWidget);
  });

  testWidgets('아이를 바꾸면 그 자리도 따라 바뀐다 — 같은 화면에서 둘이 섞인다', (t) async {
    replacePets(const [_borrowed, _mine]);
    selectPet(0);
    await _pump(t);
    expect(find.byKey(const Key('not-my-dog-banner')), findsOneWidget);

    selectPet(1);
    await t.pumpAndSettle();

    expect(find.byKey(const Key('not-my-dog-banner')), findsNothing);
    expect(find.text('우리 아이 정보 관리'), findsOneWidget);
  });
}

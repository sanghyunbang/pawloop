// 히어로 아래 "아이 고르기" 칩이 산책 요약 카드에 **붙지 않는다**.
//
// ## 무엇이 있었나
//
// 사장님이 실기기에서 보고 알려 주셨다 — 보리·뭉치 칩이 아래 카드 테두리에 그대로
// 닿아서, 칩이 카드에 딸린 줄처럼 읽혔다.
//
// 히어로가 `Expanded` 라 남은 공간을 다 먹는다. 아이가 둘이라 칩 줄이 붙으면 그 열이
// 화면을 꽉 채우고, 마지막 줄과 다음 위젯 사이에 **간격이 0** 이 된다. 아이가 하나인
// 집에서는 칩 줄이 없어서 눈에 안 띄었다.
//
// ## 왜 위젯 테스트로 재나
//
// 이 실패는 "글자가 틀렸다" 가 아니라 **두 상자의 거리**다. 찾기로는 안 잡히고 좌표를
// 재야 잡힌다. 그래서 여기서만 잡을 수 있다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';
import 'package:heat_trip_flutter/v2/widgets/dog_avatar.dart';

const _bori = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small, ageMonths: 24);
const _mungchi = DogProfile(
    serverId: 2, name: '뭉치', breed: '시바', size: DogSize.medium, ageMonths: 48);

class _Repo implements WalkRepository {
  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      const ServerWalkPage(items: [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => const ServerWalkStats(
        weekKm: [0, 0, 0, 0, 0, 0, 0],
        totalKm: 0,
        walkCount: 0,
        avgKm: 0,
        allTimeKm: 0,
        allTimeCount: 0,
        allTimeMinutes: 0,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(WidgetTester t) async {
  // **진짜 기기 폭·높이로 잰다.** 넓은 기본 화면에서는 Expanded 에 남는 공간이 많아
  // 간격이 0 이 되는 상황 자체가 안 만들어진다.
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: TodayScreen(feed: WalkFeed(repository: _Repo()))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.signInForTest(const AuthUser(id: 11, nickname: '아빠'));
    replacePets(const [_bori, _mungchi]);
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  testWidgets('아이 고르기 칩과 산책 요약 카드가 붙지 않는다', (t) async {
    await _pump(t);

    final chips = find.byKey(const Key('pet-switcher'));
    final card = find.byKey(const Key('walk-summary'));
    expect(chips, findsOneWidget, reason: '아이가 둘이면 칩 줄이 있어야 한다');
    expect(card, findsOneWidget);

    final gap = t.getTopLeft(card).dy - t.getBottomLeft(chips).dy;

    expect(gap, greaterThanOrEqualTo(8.0),
        reason: '칩이 카드에 닿으면 카드에 딸린 줄처럼 읽힌다 (지금 ${gap.toStringAsFixed(1)}px)');
  });

  testWidgets('히어로 원이 150 이다 — 이 상수가 줄면 화면 균형이 통째로 바뀐다', (t) async {
    // **이름을 낮춘 자리다.** 처음에는 '카드가 커져도 사진이 안 작아진다' 였는데, 요약 카드에
    // `SizedBox(height: 1200)` 을 넣고 돌려도 초록이었다 — `_fitOrScroll`(today_screen.dart:252)
    // 이 페이지를 `SingleChildScrollView` + `minHeight` + `IntrinsicHeight` 로 감싸서, 카드가
    // 길어지면 히어로가 눌리는 게 아니라 **스크롤이 생기기** 때문이다. 그러니 이 검사가 잡는
    // 것은 `_dogHero` 의 상수 하나뿐이다. 잡기는 잡는다(150→120 으로 바꾸면 빨개진다).
    // 요약 카드에 줄이 늘면(#708 의 문 둘) 히어로가 쓸 자리가 줄고, 히어로는 `FittedBox`
    // 안에 있어서 **자리가 모자라면 조용히 줄어든다.** 넘침도 실패도 안 나니 아무 테스트도
    // 안 잡는다 — 화면에서는 우리 아이 사진만 작아져 있다.
    //
    // `getSize` 가 아니라 `getRect` 로 잰다. `FittedBox` 는 자식의 상자 크기를 그대로 두고
    // **그리는 배율만** 바꾸므로, 상자만 재면 줄어들어도 150 이 나온다.
    //
    // 재는 것은 `DogAvatar` 가 아니라 그것을 담은 원이다 — 사진을 아직 안 올린 아이의
    // `DogAvatar` 는 이모지 96 만 그린다(`dog_avatar.dart`). 150 은 원의 지름이다.
    await _pump(t);

    final hero = find
        .ancestor(of: find.byType(DogAvatar).first, matching: find.byType(Container))
        .first;

    expect(t.getRect(hero).height, 150.0);
  });

  testWidgets('아이가 하나면 칩 줄이 없고, 그래도 카드가 이름에 안 붙는다', (t) async {
    replacePets(const [_bori]);
    await _pump(t);

    expect(find.byKey(const Key('pet-switcher')), findsNothing,
        reason: '고를 것이 하나면 고르는 줄을 안 그린다');

    final name = find.text('보리');
    final card = find.byKey(const Key('walk-summary'));
    expect(t.getTopLeft(card).dy - t.getBottomLeft(name).dy,
        greaterThanOrEqualTo(8.0));
  });
}

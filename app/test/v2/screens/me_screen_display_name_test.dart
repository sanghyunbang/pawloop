// 프로필에서 표시 이름으로 가는 문 — 이슈 #665.
//
// 서버는 `PUT /auth/me` 로 닉네임을 받을 준비가 돼 있었는데 **앱에 들어갈 문이 없었다.**
// 여기서 재는 것은 그 문이 있는가, 게스트에게는 없는가(바꿀 계정이 없다), 그리고 이름이
// 바뀌었을 때 이 화면이 **그 자리에서** 새 이름을 그리는가다.
//
// 셋째가 중요한 이유: 이름을 바꿔도 `AuthStatus` 는 그대로 `authenticated` 라, 상태만 듣는
// 화면은 옛 이름에 멈춘다. "저장은 됐는데 프로필은 그대로" 가 정확히 그 증상이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/display_name_screen.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';

/// 로그인 상태에서 화면이 서버를 부르지 않게 — 진짜 저장소는 12초 타이머를 남긴다.
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
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

const _bori = DogProfile(
    serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: MeScreen(feed: WalkFeed(repository: _Repo()))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kMyPets.value = const [_bori];
    kMyDog.value = _bori;
  });
  tearDown(() {
    AuthState.resetForTest();
    kMyPets.value = const [];
    kMyDog.value = null;
  });

  testWidgets('로그인하면 "내 정보 수정" 으로 들어갈 수 있다', (t) async {
    AuthState.signInForTest(const AuthUser(id: 7, nickname: '카카오닉'));
    await _pump(t);

    expect(find.text('내 정보 수정'), findsOneWidget);

    await t.tap(find.text('내 정보 수정'));
    await t.pumpAndSettle();

    expect(find.byType(DisplayNameScreen), findsOneWidget);
  });

  testWidgets('게스트에게는 "내 정보 수정" 이 없다 — 바꿀 계정이 없다', (t) async {
    AuthState.status.value = AuthStatus.unauthenticated;
    await _pump(t);

    expect(find.text('내 정보 수정'), findsNothing);
    expect(find.text('설정'), findsOneWidget, reason: '게스트도 설정에는 닿아야 한다(#404)');
  });

  testWidgets('이름이 바뀌면 프로필이 즉시 새 이름을 보여 준다', (t) async {
    AuthState.signInForTest(const AuthUser(id: 7, nickname: '카카오닉'));
    await _pump(t);

    expect(find.text('카카오닉'), findsOneWidget);

    // 저장에 성공한 화면이 하는 일과 같다 — 서버가 돌려준 나로 갈아 끼운다.
    AuthState.applyUpdatedUser(const {'id': 7, 'nickname': '길동이아빠'});
    await t.pump();

    expect(find.text('길동이아빠'), findsOneWidget);
    expect(find.text('카카오닉'), findsNothing,
        reason: '상태는 그대로 authenticated 라, 이 줄이 상태만 들으면 옛 이름에 멈춘다');
  });
}

// 내 프로필 메뉴 — 같은 곳으로 가는 메뉴 둘, 죽은 북마크, 내부 제공자 이름 (#332).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
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
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Widget _screen({Key? key}) => MaterialApp(key: key, home: MeScreen(feed: WalkFeed(repository: _Repo())));

const _bori = DogProfile(serverId: 1, name: 'Bori', breed: '믹스', size: DogSize.medium, ageMonths: 30);

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

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_screen());
    await t.pumpAndSettle();
  }

  testWidgets('편집으로 가는 진입점은 배너 하나 — "프로필 편집" 행과 "북마크" 행이 없다', (t) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker', provider: 'kakao'));
    await pump(t);

    expect(find.text('우리 아이 정보 관리'), findsOneWidget);
    expect(find.text('프로필 편집'), findsNothing);
    expect(find.text('북마크'), findsNothing);
    expect(find.text('내 산책 기록'), findsOneWidget, reason: '나머지 메뉴는 그대로');
  });

  testWidgets('제공자는 사람 말로 — "walker · 카카오로 로그인", local 은 안 보인다', (t) async {
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker', provider: 'kakao'));
    await pump(t);
    expect(find.text('walker · 카카오로 로그인'), findsOneWidget);

    AuthState.signInForTest(const AuthUser(id: 2, nickname: 'tester', provider: 'local'));
    await t.pumpWidget(_screen(key: const ValueKey('second')));
    await t.pumpAndSettle();
    expect(find.textContaining('· local'), findsNothing);
    expect(find.text('tester · 이메일로 로그인'), findsOneWidget);
  });

  test('providerLabel — 모르는 값은 null 이라 노출되지 않는다', () {
    expect(providerLabel('kakao'), '카카오로 로그인');
    expect(providerLabel('google'), 'Google 로 로그인');
    expect(providerLabel('apple'), 'Apple 로 로그인');
    expect(providerLabel('local'), '이메일로 로그인');
    expect(providerLabel('naver'), isNull);
    expect(providerLabel(null), isNull);
  });
}

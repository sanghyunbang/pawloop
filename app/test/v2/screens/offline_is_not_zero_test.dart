// 못 불러온 것과 안 걸은 것은 **다른 화면**이다 — 이슈 #568.
//
// ## 무엇이 있었나
//
// 서버 통계가 404 로 죽은 홈을 보니 이랬다.
//
// ```
//   0회          0.0km         0초
//         기록을 불러오지 못했어요
//  이번 주 목표  0/5일 · 0/150분
//  [                              ]   ← 빈 막대
// ```
//
// "불러오지 못했어요" 바로 위아래에 0 이 네 개다. 읽는 사람은 **"못 불러온 것"과 "안 걸은
// 것"을 구별할 수 없다.** 특히 `0/5일 · 0/150분` 과 빈 막대는 문장이 아니라 **주장**이다 —
// "이번 주에 아무것도 안 했다" 고 말하는데, 사실 앱은 이번 주에 무엇을 했는지 모른다.
//
// 윗줄은 이 경우를 알고 있었지만(`walk_feed.dart` 의 주석) 그 아래 주간 목표 줄에는
// `offline` 을 보는 코드가 한 줄도 없었다.
//
// ## 여기서 지키는 것
//
//  1. 모르면 `0` 이 아니라 `—` 다. 0 은 값이고 `—` 는 "모른다" 다.
//  2. 모르면 달성치를 **주장하지 않는다** — 목표만 남긴다. 목표는 기기에 저장된 값이라
//     서버가 죽어도 사실이다.
//  3. **아직 안 읽은 것과 못 읽은 것을 나눈다.** 첫 프레임에 "불러오지 못했어요" 가
//     깜빡이면 안 된다.
//  4. 다시 시도할 자리가 있고, 누르면 다시 읽는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

const _bori = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small, ageMonths: 24);

/// 서버가 죽은 저장소. 부른 횟수를 센다 — "다시 시도" 가 정말 다시 읽는지 보려고.
class _DeadRepo implements WalkRepository {
  int calls = 0;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async {
    calls++;
    throw const WalkFailure(WalkFailureKind.network);
  }

  @override
  Future<ServerWalkStats> stats({int? dogId}) async {
    throw const WalkFailure(WalkFailureKind.network);
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

/// **끝나지 않는** 저장소 — 자료가 오기 전의 화면을 보려고 붙잡아 둔다.
class _SlowRepo implements WalkRepository {
  final _gate = Completer<void>();

  void finish() => _gate.complete();

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async {
    await _gate.future;
    return const ServerWalkPage(items: [], nextCursor: null, hasMore: false);
  }

  @override
  Future<ServerWalkStats> stats({int? dogId}) async {
    await _gate.future;
    return const ServerWalkStats(
        weekKm: [0, 0, 0, 0, 0, 0, 0], totalKm: 0, walkCount: 0, avgKm: 0,
        allTimeKm: 0, allTimeCount: 0, allTimeMinutes: 0);
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

/// 살아 있는 저장소 — 이번 주에 한 번 걸었다.
class _LiveRepo implements WalkRepository {
  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      const ServerWalkPage(items: [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => const ServerWalkStats(
        weekKm: [1.2, 0, 0, 0, 0, 0, 0],
        weekMinutes: [30, 0, 0, 0, 0, 0, 0],
        totalKm: 1.2,
        walkCount: 1,
        avgKm: 1.2,
        allTimeKm: 1.2,
        allTimeCount: 1,
        allTimeMinutes: 30,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(WidgetTester t, WalkRepository repo) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: TodayScreen(feed: WalkFeed(repository: repo))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.signInForTest(const AuthUser(id: 11, nickname: '아빠'));
    replacePets(const [_bori]);
    selectPet(0);
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
  });

  testWidgets('못 불러오면 숫자가 0 이 아니라 — 다 (#568)', (t) async {
    await _pump(t, _DeadRepo());

    expect(find.text('0회'), findsNothing,
        reason: '"0회" 는 "안 걸었다" 는 주장이다. 못 불러온 것과 구별이 안 된다');
    expect(find.text('0.0km'), findsNothing);
    expect(find.text('기록을 불러오지 못했어요'), findsOneWidget);
    // 셋(오늘 산책 · 거리 · 시간) 다 모른다.
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('낭독기에는 "모름" 이라고 말한다 — `—` 는 소리로 안 읽힌다 (#568)', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, _DeadRepo());

    // **RegExp 로 찾는다.** 요약 카드가 자식들의 의미를 한 마디로 합쳐서, 낭독기가 읽는
    // 이름표는 "오늘 산책 모름 오늘 산책 거리 모름 거리 …" 처럼 이어 붙은 한 줄이다.
    // 정확히 같은 문자열로 찾으면 못 찾는다 — 이름표가 없어서가 아니다.
    expect(find.bySemanticsLabel(RegExp('오늘 산책 모름')), findsOneWidget,
        reason: '눈으로는 "모른다" 인데 귀로는 빈칸이면, 화면을 못 보는 사람에게는 '
            '고치기 전과 똑같이 0 과 구별이 안 된다');
    expect(find.bySemanticsLabel(RegExp('거리 모름')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('시간 모름')), findsOneWidget);

    handle.dispose();
  });

  testWidgets('못 불러오면 주간 목표가 달성치를 주장하지 않는다 (#568)', (t) async {
    await _pump(t, _DeadRepo());

    final label = t.widget<Text>(find.byKey(const Key('walk-goal-label')));
    expect(label.data, '5일 · 150분',
        reason: '"0/5일 · 0/150분" 과 빈 막대는 "이번 주에 아무것도 안 했다" 는 주장이다');
    expect(label.data, isNot(contains('/')));
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: '값 0 은 "하나도 못 채웠다" 로, 도는 막대는 "읽는 중" 으로 읽힌다');
  });

  testWidgets('다시 시도를 누르면 다시 읽는다 — 지금은 화면을 떠났다 오는 길뿐이다 (#568)',
      (t) async {
    final repo = _DeadRepo();
    await _pump(t, repo);
    expect(repo.calls, 1);

    await t.tap(find.byKey(const Key('walk-feed-retry')));
    await t.pumpAndSettle();

    expect(repo.calls, 2);
    expect(find.text('기록을 불러오지 못했어요'), findsOneWidget,
        reason: '또 실패했으니 같은 말을 한다 — 대신 눌린 것은 보여야 한다');
  });

  testWidgets('불러오면 숫자가 돌아온다 — 정상 화면은 그대로다', (t) async {
    await _pump(t, _LiveRepo());

    expect(find.text('기록을 불러오지 못했어요'), findsNothing);
    expect(find.text('—'), findsNothing);
    final label = t.widget<Text>(find.byKey(const Key('walk-goal-label')));
    expect(label.data, contains('/'), reason: '아는 주에는 달성치를 그린다');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('읽는 동안에는 "불러오지 못했어요" 를 말하지 않는다 (#568)', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    final repo = _SlowRepo();

    await t.pumpWidget(MaterialApp(home: TodayScreen(feed: WalkFeed(repository: repo))));
    await t.pump();

    expect(find.text('기록을 불러오지 못했어요'), findsNothing,
        reason: '아직 안 읽은 것은 못 읽은 것이 아니다. empty 가 offline: true 뿐이라 깜빡였다');
    expect(find.byKey(const Key('walk-feed-retry')), findsNothing,
        reason: '읽는 중인데 "다시 시도" 를 내밀 이유가 없다');
    expect(find.text('—'), findsNWidgets(3), reason: '모르는 동안에도 0 은 주장이다');

    repo.finish();
    await t.pumpAndSettle();

    expect(find.text('0회'), findsOneWidget,
        reason: '읽고 나면 0 은 사실이다 — 그때는 0 이라고 말해야 한다');
  });
}

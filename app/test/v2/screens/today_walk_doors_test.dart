// 홈 요약 카드 맨 아래의 문 둘 — 이슈 #708.
//
// ## 무엇이 있었나
//
// 통계로 가는 문은 원래 있었다. 요약 카드 **전체**가 `InsightScreen` 으로 가는 손을 달고
// 있었는데 셰브론도 글자도 낭독기 라벨도 없었다 — 누를 수 있다는 표시가 하나도 없는 문이라
// 아무도 못 찾았다. 기록 목록은 그나마도 없어서 홈 → 아바타 → 내 프로필 → 내 산책 기록,
// 네 걸음이었다.
//
// ## 왜 화면까지 띄우나
//
// "문이 있다" 는 **보이는 이름표**와 **닿는 화면** 둘 다여야 성립한다. 위젯 하나만 재면
// 이름표는 있는데 눌러도 아무 데도 안 가는 경우를 못 잡는다. 그래서 홈 전체를 띄우고
// 실제로 눌러서 화면이 바뀌는지 본다.
//
// 게스트 쪽(문이 **없어야** 한다)은 `today_screen_guest_test.dart` 에 있다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';
import 'package:heat_trip_flutter/v2/screens/today_screen.dart';

const _bori = DogProfile(
    serverId: 1, name: '보리', breed: '푸들', size: DogSize.small, ageMonths: 24);

/// 홈이 서버를 안 부르게 갈아 끼우는 저장소 — `today_summary_seconds_test.dart` 의 것과 같다.
class _Repo implements WalkRepository {
  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: [_walkToday()], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => const ServerWalkStats(
        weekKm: [0, 0, 0, 0, 0, 0, 0],
        totalKm: 0.7,
        walkCount: 1,
        avgKm: 0.7,
        allTimeKm: 0.7,
        allTimeCount: 1,
        // 요약 카드의 값과 겹치지 않는 수 — 겹치면 find.text 가 둘을 찾는다.
        allTimeMinutes: 99,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalk _walkToday() {
  final now = DateTime.now();
  return ServerWalk(
    id: 14,
    dogId: 1,
    dogIds: const [1],
    clientWalkId: 'ck-14',
    startedAt: DateTime(now.year, now.month, now.day, 8, 30),
    distanceM: 704,
    durationS: 720,
  );
}

/// 이름표와 문이 **가는 곳**을 재는 판. 폭을 넉넉히 둔다 — 여기서 재는 것은 배치가 아니다.
Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    home: TodayScreen(feed: WalkFeed(repository: _Repo())),
  ));
  await t.pumpAndSettle();
}

/// 좁은 실기기 폭(360dp)에서 **글자 배율**만 바꿔 가며 재는 판.
///
/// **한동안 아이를 등록 안 한 집으로 돌렸다.** 목표 줄(`WalkGoalRow`)이 360dp 에서
/// `이번 주 목표 1/5일 · 12/150분` + `1일째` 를 가로로 못 담아 1.0배에 16px · 2.0배에 289px
/// 넘쳤고, 그 넘침까지 여기서 받으면 이 테스트가 무엇 때문에 빨간지 알 수 없었기 때문이다.
/// 그 넘침은 `walk_goal_row.dart` 의 `_labelLine` 이 고쳤고, 지키는 검사는
/// `today_screen_text_scale_test.dart` 의 로그인 판에 있다. 그래서 **아이를 등록한 채로
/// 돌린다** — 실기기에서 제일 흔한 판이고, 목표 줄과 문 줄이 같은 화면에 있는 모양이다.
Future<void> _pumpNarrow(WidgetTester t, double scale) async {
  const ratio = 3.0;
  t.view.physicalSize = const Size(360 * ratio, 780 * ratio);
  t.view.devicePixelRatio = ratio;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    home: Builder(
      // 화면 크기는 view 에서 온 것을 그대로 두고 글자 배율만 바꾼다 — MediaQueryData 를
      // 통째로 새로 만들면 size 가 0 이 되어 다른 것을 재게 된다.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: TodayScreen(feed: WalkFeed(repository: _Repo())),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// 눌러서 연 화면의 **기다림을 끝까지 돌려 준다.**
///
/// 홈은 문을 `const MyRecordsScreen()` · `const InsightScreen()` 으로 연다 — 테스트가 피드를
/// 끼울 자리가 없어서, 열린 화면은 진짜 저장소를 만들고 서버를 부른다. 위젯 테스트에서 그
/// 요청은 400 으로 돌아오지만 `_send` 의 9초 제한 타이머가 남고, 그대로 끝내면
/// "A Timer is still pending" 으로 테스트가 빨개진다. 여기서 시간을 그만큼 밀어 타이머를
/// 거둔다 — 화면이 열렸다는 사실은 이미 위에서 쟀다.
Future<void> _letPushedScreenGiveUp(WidgetTester t) async {
  await t.pump(const Duration(seconds: 10));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
    replacePets(const [_bori]);
  });
  tearDown(() {
    AuthState.resetForTest();
    replacePets(const []);
    kMyDog.value = null;
  });

  testWidgets('로그인 홈에 "내 산책 기록" 과 "산책 통계" 가 하나씩 있다', (t) async {
    await _pump(t);

    // 이름이 없으면 문이 아니다 — 고치기 전에는 카드 전체가 손이었을 뿐 글자가 없었다.
    expect(find.text('내 산책 기록'), findsOneWidget);
    expect(find.text('산책 통계'), findsOneWidget);
  });

  testWidgets('"내 산책 기록" 을 누르면 기록 화면이 뜬다', (t) async {
    await _pump(t);

    await t.tap(find.byKey(const Key('home-my-records')));
    await t.pumpAndSettle();

    expect(find.byType(MyRecordsScreen), findsOneWidget,
        reason: '고치기 전에는 여기까지 네 걸음이었다 — 산책 앱에서 내 산책이 가장 깊은 곳에 있었다');

    await _letPushedScreenGiveUp(t);
  });

  testWidgets('"산책 통계" 를 누르면 통계 화면이 뜬다', (t) async {
    await _pump(t);

    await t.tap(find.byKey(const Key('home-walk-stats')));
    await t.pumpAndSettle();

    expect(find.byType(InsightScreen), findsOneWidget,
        reason: '문은 원래 있었다 — 이름표를 붙였을 뿐이라 가는 곳이 그대로여야 한다');

    await _letPushedScreenGiveUp(t);
  });

  testWidgets('아이를 아직 등록 안 했어도 문 둘은 있다 — 목표 줄만 없다', (t) async {
    // 아이가 없으면 `WalkGoalRow` 가 통째로 사라진다(`walk_goal_row.dart:100`).
    // 그때 구분선과 문까지 함께 없어지면 기록으로 가는 길이 **등록한 사람에게만** 생긴다 —
    // 아이를 등록하기 전에 걸어 본 산책도 기록에는 남는다.
    replacePets(const []);
    kMyDog.value = null;
    await _pump(t);

    expect(find.byKey(const Key('walk-goal-label')), findsNothing,
        reason: '아이가 없으면 권장 산책량을 지어내지 않는다');
    expect(find.text('내 산책 기록'), findsOneWidget);
    expect(find.text('산책 통계'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('360dp · 글자 $scale배에서 문 둘이 안 넘친다', (t) async {
      // 1.3배부터는 나란히 두지 않고 위아래로 세운다. 접지 않는 이유는 문을 접으면 기능이
      // 없어지기 때문이다 — 1.5배는 삼성 One UI 슬라이더로 닿는 값이라 특별한 설정이 아니다.
      await _pumpNarrow(t, scale);

      expect(t.takeException(), isNull);
      expect(find.text('내 산책 기록'), findsOneWidget);
      expect(find.text('산책 통계'), findsOneWidget);
    });
  }

  testWidgets('글자를 키우면 문 둘이 위아래로 선다 — 이름이 안 잘린다', (t) async {
    await _pumpNarrow(t, 1.5);

    final records = t.getRect(find.text('내 산책 기록'));
    final stats = t.getRect(find.text('산책 통계'));
    expect(stats.top, greaterThan(records.bottom),
        reason: '나란히 두면 폭이 반이라 "내 산책 …" 으로 잘린다 — 무엇을 누르는지 알 수 없다');
  });

  testWidgets('1.0배에서는 문 둘이 나란하다 — 평소 화면을 안 바꾼다', (t) async {
    await _pumpNarrow(t, 1.0);

    final records = t.getRect(find.text('내 산책 기록'));
    final stats = t.getRect(find.text('산책 통계'));
    expect(stats.left, greaterThan(records.right));
  });

  testWidgets('누를 자리가 36pt 이상이다 — 글자 높이만큼만 두면 걸으면서 못 누른다', (t) async {
    // **시뮬레이터에서 눈으로 보고 고친 자리다.** 처음에는 글자만 감싸서 누를 높이가
    // 17pt 였다 — 애플 지침(HIG, Layout)이 44×44pt 를 권하는데 그 절반도 안 됐다.
    // 산책 앱이라 사람들이 **걸으면서 한 손으로** 누른다. 지금은 위아래 11 을 넣어
    // 39pt 다.
    //
    // 36 으로 재는 이유: 44 를 요구하면 카드가 더 커지고, 그러면 홈이 한 화면에서
    // 더 밀려난다. 39 는 그 사이에서 고른 값이고, 이 검사는 **다시 17pt 로 줄어드는
    // 것**을 막는 자리다.
    await _pump(t);

    for (final key in const [Key('home-my-records'), Key('home-walk-stats')]) {
      final box = t.getRect(find.byKey(key));
      expect(box.height, greaterThanOrEqualTo(36), reason: '''
$key 의 누를 높이가 ${box.height.toStringAsFixed(1)}pt 다. 글자만 감싸면 17pt 가 되고,
걸으면서 누르면 자주 빗나간다.''');
    }
  });

  testWidgets('낭독기가 버튼으로 읽는다 — 이 변경의 명분 절반이 여기다', (t) async {
    // **검증 담당이 찾은 구멍이다.** 이 변경의 이유가 "셰브론도 글자도 **낭독기 라벨도**
    // 없어 아무도 못 찾았다" 인데, `_door` 의 `Semantics` 를 통째로 걷어내고 돌려도
    // 열세 검사가 전부 초록이었다. 명분으로 삼은 것을 아무도 안 재고 있었다.
    final handle = t.ensureSemantics();
    await _pump(t);

    // `find.bySemanticsLabel` 은 안 쓴다 — 라벨이 정확히 일치하는 **노드**를 찾는데,
    // 여기서는 `Semantics` 의 라벨과 안쪽 `Text` 의 라벨이 한 노드로 합쳐져 0건이 나온다.
    // 키로 집어 그 자리의 노드를 직접 본다.
    for (final (key, label) in const [
      (Key('home-my-records'), '내 산책 기록'),
      (Key('home-walk-stats'), '산책 통계'),
    ]) {
      final node = t.getSemantics(find.byKey(key));
      expect(node.label, contains(label), reason: '낭독기가 "$label" 을 못 읽는다');
      // `matchesSemantics` 는 나머지 플래그까지 전부 맞추라고 해서 안 쓴다 — 여기서
      // 재려는 것은 **버튼으로 읽히는가** 하나다.
      expect(node.flagsCollection.isButton, isTrue,
          reason: '"$label" 은 눌러서 가는 자리인데 낭독기가 버튼이라고 말하지 않는다');
    }
    handle.dispose();
  });
}

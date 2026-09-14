// AI 요약 👍/👎 (#486 후속) — 누르면 바로 채워지고 서버에 한 번, 같은 것을 다시 누르면 지우고, 실패하면 되돌린다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/weekly_summary.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';

const _text = '이번 주는 3회 걸어 3.2km 를 채웠어요.\n아침 산책이 잘 맞아요.\n주말에 한 번 더 어떠세요?';

class _Repo implements WalkRepository {
  _Repo({required this.aiSummary});

  final AiSummary? aiSummary;

  /// (id, value) 순서대로.
  final List<(int, String?)> rated = [];
  bool fail = false;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: const [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: const [1.0, 0, 1.2, 0, 1.0, 0, 0],
        weekMinutes: const [30, 0, 30, 0, 30, 0, 0],
        totalKm: 3.2,
        walkCount: 3,
        avgKm: 1.07,
        allTimeKm: 3.2,
        allTimeCount: 3,
        allTimeMinutes: 90,
        topPlaces: const [],
        summary: WeekSummaryData.empty,
        aiSummary: aiSummary,
      );

  @override
  Future<AiSummary> rateInsight(int insightId, String? value) async {
    rated.add((insightId, value));
    if (fail) throw const WalkFailure(WalkFailureKind.network);
    return aiSummary!.withFeedback(value);
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<_Repo> _pump(WidgetTester t, {AiSummary? aiSummary, bool fail = false}) async {
  final repo = _Repo(aiSummary: aiSummary)..fail = fail;
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: InsightScreen(feed: WalkFeed(repository: repo))));
  await t.pumpAndSettle();
  return repo;
}

Finder _up() => find.byKey(const Key('ai-feedback-up'));
Finder _down() => find.byKey(const Key('ai-feedback-down'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(AuthState.resetForTest);

  testWidgets('👍 를 누르면 바로 채워지고 서버에 (id, up) 한 번', (t) async {
    final repo = await _pump(t, aiSummary: const AiSummary(id: 7, text: _text));
    await t.ensureVisible(_up());
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget, reason: '아직 안 눌렀다');

    await t.tap(_up());
    await t.pumpAndSettle();

    expect(repo.rated, [(7, 'up')]);
    expect(find.byIcon(Icons.thumb_up_rounded), findsOneWidget, reason: '채워진 엄지');
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget, reason: '반대쪽은 그대로');
  });

  testWidgets('같은 것을 다시 누르면 지운다 — 서버에 null', (t) async {
    final repo = await _pump(t, aiSummary: const AiSummary(id: 7, text: _text, feedback: 'up'));
    await t.ensureVisible(_up());
    expect(find.byIcon(Icons.thumb_up_rounded), findsOneWidget, reason: '서버가 준 평가로 시작한다');

    await t.tap(_up());
    await t.pumpAndSettle();

    expect(repo.rated, [(7, null)]);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('👎 로 바꾸면 (id, down) 이고 👍 는 비워진다', (t) async {
    final repo = await _pump(t, aiSummary: const AiSummary(id: 7, text: _text, feedback: 'up'));
    await t.ensureVisible(_down());

    await t.tap(_down());
    await t.pumpAndSettle();

    expect(repo.rated, [(7, 'down')]);
    expect(find.byIcon(Icons.thumb_down_rounded), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('서버가 실패하면 되돌리고 한 줄 알린다', (t) async {
    await _pump(t, aiSummary: const AiSummary(id: 7, text: _text), fail: true);
    await t.ensureVisible(_up());

    await t.tap(_up());
    await t.pumpAndSettle();

    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget, reason: '채워졌다가 되돌아온다');
    expect(find.byIcon(Icons.thumb_up_rounded), findsNothing);
    expect(find.textContaining('지금은 보낼 수 없어요'), findsOneWidget);
  });

  testWidgets('옛 서버(id 없음)면 카드는 있고 엄지는 없다', (t) async {
    await _pump(t, aiSummary: const AiSummary(text: _text));

    expect(find.byKey(const Key('ai-summary')), findsOneWidget);
    expect(_up(), findsNothing);
    expect(_down(), findsNothing);
  });
}

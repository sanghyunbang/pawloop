// 모델 호출 비동기화 — 서버가 "만드는 중" 이라 하면 한 줄 카드를 두고 4초 뒤 한 번 더 읽는다(세 번까지).
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
  /// 통계를 부를 때마다 앞에서부터 하나씩 — 다 쓰면 마지막 것을 되풀이한다.
  _Repo(this.responses);

  final List<ServerWalkStats> responses;
  int calls = 0;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: const [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async {
    final i = calls < responses.length ? calls : responses.length - 1;
    calls++;
    return responses[i];
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalkStats _stats({AiSummary? ai, bool pending = false}) => ServerWalkStats(
      weekKm: const [1.0, 0, 1.2, 0, 1.0, 0, 0],
      weekMinutes: const [30, 0, 30, 0, 30, 0, 0],
      totalKm: 3.2,
      walkCount: 3,
      avgKm: 1.07,
      allTimeKm: 3.2,
      allTimeCount: 3,
      allTimeMinutes: 90,
      summary: WeekSummaryData.empty,
      aiSummary: ai,
      aiSummaryPending: pending,
    );

Future<_Repo> _pump(WidgetTester t, List<ServerWalkStats> responses) async {
  final repo = _Repo(responses);
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: InsightScreen(feed: WalkFeed(repository: repo))));
  await t.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(AuthState.resetForTest);

  testWidgets('만드는 중이면 한 줄 카드가 있고, 4초 뒤 다시 읽어 문장이 오면 요약 카드가 그 자리를 잇는다', (t) async {
    final repo = await _pump(t, [
      _stats(pending: true),
      _stats(ai: const AiSummary(id: 7, text: _text)),
    ]);

    expect(find.byKey(const Key('ai-summary-pending')), findsOneWidget);
    expect(find.byKey(const Key('ai-summary')), findsNothing);
    expect(repo.calls, 1);

    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();

    expect(repo.calls, 2, reason: '4초 뒤 한 번 더 읽었다');
    expect(find.byKey(const Key('ai-summary-pending')), findsNothing);
    expect(find.byKey(const Key('ai-summary')), findsOneWidget);
  });

  testWidgets('계속 만드는 중이면 세 번까지만 다시 읽는다 — 영원히 두드리지 않는다', (t) async {
    final repo = await _pump(t, [_stats(pending: true)]);

    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
    }

    expect(repo.calls, 4, reason: '처음 한 번 + 다시 읽기 세 번');
    expect(find.byKey(const Key('ai-summary-pending')), findsOneWidget, reason: '카드는 그대로 둔다');
  });

  testWidgets('만드는 중이 아니면 다시 읽지 않는다', (t) async {
    final repo = await _pump(t, [_stats()]);

    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();

    expect(repo.calls, 1);
    expect(find.byKey(const Key('ai-summary-pending')), findsNothing);
    expect(find.textContaining('AI'), findsNothing, reason: '만드는 중도 아니고 문장도 없으면 AI 라는 글자가 없다');
  });

  testWidgets('옛 문장을 새로 만드는 중이면 옛 문장을 그대로 그리고 조용히 바꾼다', (t) async {
    const old = AiSummary(id: 7, text: '지난 문장.\n둘째 줄.\n제안.');
    const fresh = AiSummary(id: 7, text: _text);
    final repo = await _pump(t, [_stats(ai: old, pending: true), _stats(ai: fresh)]);

    expect(find.byKey(const Key('ai-summary')), findsOneWidget);
    expect(find.byKey(const Key('ai-summary-pending')), findsNothing, reason: '옛 문장이 있으면 만드는 중 카드는 없다');
    expect(find.textContaining('지난 문장'), findsOneWidget);

    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();

    expect(repo.calls, 2);
    expect(find.descendant(of: find.byKey(const Key('ai-summary')), matching: find.textContaining('3.2km')),
        findsOneWidget, reason: '새 문장으로 바뀌었다');
    expect(find.textContaining('지난 문장'), findsNothing);
  });
}

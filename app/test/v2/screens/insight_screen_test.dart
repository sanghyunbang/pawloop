// 산책 통계 — "AI" 라벨이 없고, 눈금이 0 0 0 0 이 아니고, 자주 가는 곳이 말을 한다 (#332).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/domain/weekly_summary.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';

class _Repo implements WalkRepository {
  _Repo(this.weekKm, {this.topPlaces = const [], this.weekMinutes, this.summary, this.aiSummary});
  final List<double> weekKm;
  final List<WalkTopPlace> topPlaces;

  /// 요일별 분. 안 주면 걸은 요일마다 30분으로 채운다 — 요약이 분을 읽는다(#359).
  final List<int>? weekMinutes;

  /// 서버가 주는 "이번 주 요약" 계산 결과 (#359).
  final WeekSummaryData? summary;

  /// 서버가 모델로 만든 "AI 요약" (#486). 없으면 카드도 라벨도 없다.
  final AiSummary? aiSummary;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: const [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: weekKm,
        weekMinutes: weekMinutes ?? [for (final km in weekKm) km > 0 ? 30 : 0],
        totalKm: weekKm.fold(0.0, (a, b) => a + b),
        walkCount: weekKm.where((k) => k > 0).length,
        avgKm: 0.15,
        allTimeKm: 0.15,
        allTimeCount: 1,
        allTimeMinutes: 1,
        topPlaces: topPlaces,
        summary: summary ?? WeekSummaryData.empty,
        aiSummary: aiSummary,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(
  WidgetTester t,
  List<double> weekKm, {
  List<WalkTopPlace> topPlaces = const [],
  List<int>? weekMinutes,
  WeekSummaryData? summary,
  AiSummary? aiSummary,
}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: InsightScreen(
      feed: WalkFeed(
        repository: _Repo(weekKm,
            topPlaces: topPlaces, weekMinutes: weekMinutes, summary: summary, aiSummary: aiSummary),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(AuthState.resetForTest);

  test('axisLabel — 1km 미만은 m, 그 위는 소수 첫째 자리', () {
    expect(axisLabel(0.05), '50m');
    expect(axisLabel(0.1875), '188m');
    expect(axisLabel(1.0), '1.0');
    expect(axisLabel(2.5), '2.5');
  });

  testWidgets('"AI 주간 리포트"·"베타"·시스템 이모지가 없고 "이번 주 요약" 이다', (t) async {
    await _pump(t, const [0.15, 0, 0, 0, 0, 0, 0]);

    expect(find.textContaining('AI'), findsNothing);
    expect(find.text('베타'), findsNothing);
    expect(find.textContaining('🐾'), findsNothing);
    expect(find.text('이번 주 요약'), findsOneWidget);
    expect(find.textContaining('이번 주 1회'), findsOneWidget, reason: '문장 자체는 자료에서 나온다');
  });

  testWidgets('0.15km 한 건이면 세로축이 "0 0 0 0" 이 아니라 m 눈금이다', (t) async {
    await _pump(t, const [0.15, 0, 0, 0, 0, 0, 0]);

    expect(find.text('0'), findsNothing, reason: '정수 반올림 눈금');
    expect(find.textContaining('m'), findsWidgets);
  });

  testWidgets('자주 가는 곳이 비어 있으면 무엇을 하면 쌓이는지 말한다', (t) async {
    await _pump(t, const [0, 0, 0, 0, 0, 0, 0]);

    expect(find.text('자주 가는 곳'), findsOneWidget);
    expect(find.textContaining('아직 없어요'), findsOneWidget);
    expect(find.textContaining('장소를 고르면'), findsOneWidget);
  });

  testWidgets('서버가 센 값을 순서대로 그린다 — 더미 문자열이 아니다 (#338)', (t) async {
    await _pump(t, const [0.2, 0, 0, 0, 0, 0, 0], topPlaces: const [
      WalkTopPlace(
        place: WalkPlaceRef(title: '서울숲', source: 'kto', contentId: '2733967'),
        count: 6,
      ),
      WalkTopPlace(
        place: WalkPlaceRef(title: 'DMZ 평화의 길', source: 'trail', contentId: 'trail:41'),
        count: 2,
      ),
    ]);

    expect(find.text('서울숲'), findsOneWidget);
    expect(find.text('DMZ 평화의 길'), findsOneWidget);
    expect(find.textContaining('아직 없어요'), findsNothing);
  });
  // ── 이번 주 요약 (#359 1단계) ────────────────────────────
  //
  // 문장은 `WeeklySummary` 가 만든다 — 여기서는 **화면이 그것을 그리는가**만 본다.
  // 문장 규칙 자체는 `weekly_summary_test.dart` 가 잰다.

  testWidgets('지난주 기록이 있으면 화면에 비교 줄이 나온다', (t) async {
    await _pump(
      t,
      const [2, 0, 2, 0, 0, 0, 0],
      weekMinutes: const [30, 0, 30, 0, 0, 0, 0],
      summary: const WeekSummaryData(lastWeekKm: 2.0, lastWeekMinutes: 30, lastWeekCount: 1),
    );

    expect(find.textContaining('지난주보다 2.0km 더 걸었어요'), findsOneWidget);
  });

  testWidgets('서버가 요약을 안 줘도 화면이 죽지 않는다 — 옛 서버와 붙어도 그린다', (t) async {
    await _pump(t, const [2, 0, 0, 0, 0, 0, 0]);

    expect(find.textContaining('이번 주 1회'), findsOneWidget);
    expect(find.textContaining('지난주'), findsNothing, reason: '없는 비교를 지어내지 않는다');
  });

  testWidgets('기록이 없으면 숫자 대신 한 줄만 말한다', (t) async {
    await _pump(t, const [0, 0, 0, 0, 0, 0, 0]);

    expect(find.text('이번 주는 아직 기록이 없어요. 오늘 한 바퀴 어때요.'), findsOneWidget);
  });

  // ── AI 요약 (#486) ─────────────────────────────────────────
  testWidgets('서버가 AI 요약을 주면 규칙 카드 아래 "AI 요약 · 베타" 카드 — 두 문장과 제안 한 줄', (t) async {
    await _pump(t, const [1.5, 0, 0, 0, 0, 0, 0],
        aiSummary: const AiSummary(
            text: '이번 주는 1회 걸어 1.5km 를 채웠어요.\n아침 산책이 잘 맞는 것 같아요.\n내일 한 번 더 어떠세요?'));

    expect(find.byKey(const Key('ai-summary')), findsOneWidget);
    expect(find.text('AI 요약'), findsOneWidget);
    expect(find.text('베타'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ai-summary')), matching: find.textContaining('1.5km')), findsOneWidget);
    expect(find.text('내일 한 번 더 어떠세요?'), findsOneWidget, reason: '마지막 줄은 제안 — 따로 굵게');
    expect(find.text('이번 주 요약'), findsOneWidget, reason: '규칙 카드는 그대로 있다 — AI 카드는 그 아래에 더해진다');
  });

  testWidgets('AI 요약이 없으면 카드도 "AI" 라는 글자도 화면에 없다 — 정직한 라벨(#347)', (t) async {
    await _pump(t, const [1.5, 0, 0, 0, 0, 0, 0]);

    expect(find.byKey(const Key('ai-summary')), findsNothing);
    expect(find.textContaining('AI'), findsNothing);
    expect(find.text('베타'), findsNothing);
  });
}

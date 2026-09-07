// 산책 통계 — "AI" 라벨이 없고, 눈금이 0 0 0 0 이 아니고, 자주 가는 곳이 말을 한다 (#332).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/insight_screen.dart';

class _Repo implements WalkRepository {
  _Repo(this.weekKm);
  final List<double> weekKm;

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: const [], nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: weekKm,
        totalKm: weekKm.fold(0.0, (a, b) => a + b),
        walkCount: weekKm.where((k) => k > 0).length,
        avgKm: 0.15,
        allTimeKm: 0.15,
        allTimeCount: 1,
        allTimeMinutes: 1,
      );

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<void> _pump(WidgetTester t, List<double> weekKm) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: InsightScreen(feed: WalkFeed(repository: _Repo(weekKm)))));
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
    expect(find.textContaining('이번 주는 1회'), findsOneWidget, reason: '문장 자체는 자료에서 나온다');
  });

  testWidgets('0.15km 한 건이면 세로축이 "0 0 0 0" 이 아니라 m 눈금이다', (t) async {
    await _pump(t, const [0.15, 0, 0, 0, 0, 0, 0]);

    expect(find.text('0'), findsNothing, reason: '정수 반올림 눈금');
    expect(find.textContaining('m'), findsWidgets);
  });

  testWidgets('자주 가는 곳이 비어 있으면 그 말을 한다', (t) async {
    await _pump(t, const [0, 0, 0, 0, 0, 0, 0]);

    expect(find.text('자주 가는 곳'), findsOneWidget);
    expect(find.textContaining('아직 없어요'), findsOneWidget);
  });
}

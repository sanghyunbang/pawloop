// 산책을 지울 수 있는가, 거절된 기록이 화면에 닿는가 — 이슈 #161.
//
// ## 여기서 재는 것
//
//  1. 잘못 저장한 산책을 **지울 길이 있는가.** 계약이 이 자리의 존재 이유를 적어
//     두었다 — 멱등키가 있어 같은 산책을 두 번 저장할 수 없으므로, 잘못 저장한 것을
//     사용자가 지울 길이 반드시 있어야 한다(`DELETE /api/walks/{walkId}`).
//     서버도 저장소도 있었고 **화면 한 층만 비어 있었다.**
//
//  2. 서버가 거절한 기록이 **화면에 남는가.** `WalkOutbox.reject` 는 초안을 지우지
//     않고 거절 큐로 옮기는데, 그 큐를 읽는 화면이 하나도 없었다. 큐에만 있고
//     화면에 없으면 그건 사라진 것과 같다.
//
//  3. 전송 대기 중인 것은 **못 지운다.** 올라가는 중에 지우면 서버에는 남고 화면에서만
//     사라진다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_outbox.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/myrecords_screen.dart';

/// 정해 둔 대로 답하는 저장소. 네트워크도 `AuthedClient` 도 타지 않는다.
class _Repo implements WalkRepository {
  _Repo({this.items = const [], this.deleteFails});

  List<ServerWalk> items;
  WalkFailure? deleteFails;

  final List<int> deleted = [];

  @override
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async =>
      ServerWalkPage(items: items, nextCursor: null, hasMore: false);

  @override
  Future<ServerWalkStats> stats({int? dogId}) async => ServerWalkStats(
        weekKm: const [0, 0, 0, 0, 0, 0, 0],
        totalKm: 0,
        walkCount: 0,
        avgKm: 0,
        allTimeKm: 2.4,
        allTimeCount: items.length,
        allTimeMinutes: 30,
      );

  @override
  Future<void> deleteWalk(int walkId) async {
    deleted.add(walkId);
    final f = deleteFails;
    if (f != null) throw f;
  }

  @override
  Future<List<ServerPet>> pets() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

ServerWalk walkOf({int id = 7, int distanceM = 2400}) => ServerWalk(
      id: id,
      dogId: 1,
      clientWalkId: 'ck-$id',
      startedAt: DateTime(2026, 9, 1, 9, 0),
      distanceM: distanceM,
      durationS: 1800,
    );

WalkDraft draftOf({String key = 'draft-1', String? error}) => WalkDraft(
      clientWalkId: key,
      startedAt: DateTime(2026, 9, 1, 8, 0),
      endedAt: DateTime(2026, 9, 1, 8, 30),
      distanceM: 1200,
      durationS: 1800,
      path: const [],
      memo: '동네 한 바퀴',
      lastError: error,
    );

Future<void> _pump(WidgetTester t, _Repo repo) async {
  await t.pumpWidget(MaterialApp(
    home: MyRecordsScreen(
      feed: WalkFeed(repository: repo),
      repository: repo,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => walkFeedRevision.value = 0);

  group('저장한 산책 지우기', () {
    testWidgets('길게 누르면 확인부터 묻는다 — 하드 삭제라 되돌릴 수 없다', (t) async {
      final repo = _Repo(items: [walkOf()]);
      await _pump(t, repo);

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();

      expect(find.text('이 기록을 지울까요?'), findsOneWidget);
      expect(repo.deleted, isEmpty, reason: '묻기 전에 지우면 안 된다');
    });

    testWidgets('취소하면 아무것도 안 지운다', (t) async {
      final repo = _Repo(items: [walkOf()]);
      await _pump(t, repo);

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();

      expect(repo.deleted, isEmpty);
    });

    testWidgets('지우기를 누르면 그 산책의 id 로 서버를 부른다', (t) async {
      final repo = _Repo(items: [walkOf(id: 42)]);
      await _pump(t, repo);

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();

      expect(repo.deleted, [42]);
    });

    testWidgets('지운 뒤 다시 불러온다 — 요약 숫자가 즉시 줄어야 한다', (t) async {
      final repo = _Repo(items: [walkOf(id: 42)]);
      await _pump(t, repo);
      final before = walkFeedRevision.value;

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();

      expect(walkFeedRevision.value, greaterThan(before),
          reason: '목록에서만 빼면 요약(서버 집계)은 낡은 값으로 남는다');
    });

    testWidgets('서버가 거절하면 사유를 말한다 — 조용히 성공한 척하지 않는다', (t) async {
      final repo = _Repo(
        items: [walkOf()],
        deleteFails: const WalkFailure(WalkFailureKind.rateLimited),
      );
      await _pump(t, repo);

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();

      expect(find.text(WalkFailureKind.rateLimited.message), findsOneWidget);
      expect(find.text('기록을 지웠어요'), findsNothing);
    });
  });

  group('올리지 못한 기록', () {
    testWidgets('거절 큐가 화면에 사유와 함께 나온다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(), '메모가 너무 길어요');

      await _pump(t, _Repo());

      expect(find.text('올리지 못한 기록'), findsOneWidget);
      expect(find.text('못 올림'), findsOneWidget);
      expect(find.text('메모가 너무 길어요'), findsOneWidget);
    });

    testWidgets('사용자가 쓴 메모를 오류 문자열로 덮지 않는다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(), '메모가 너무 길어요');

      await _pump(t, _Repo());

      expect(find.text('동네 한 바퀴'), findsOneWidget,
          reason: '사유는 따로 나른다 — 사용자가 쓴 글을 덮으면 그것도 잃는 것이다');
    });

    testWidgets('거절된 것을 지우면 기기 큐에서 빠지고 서버는 안 부른다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(key: 'gone'), '메모가 너무 길어요');
      final repo = _Repo();
      await _pump(t, repo);

      await t.longPress(find.textContaining('길게 눌러 지우기'));
      await t.pumpAndSettle();
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();

      final after = await WalkOutbox.open();
      expect(after.rejected, isEmpty);
      expect(repo.deleted, isEmpty, reason: '서버에 없는 것을 서버에 지워 달라고 하면 404 다');
    });

    testWidgets('빈 화면 문구가 거절된 것을 덮지 않는다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(), '메모가 너무 길어요');

      await _pump(t, _Repo());

      expect(find.text('아직 산책 기록이 없어요'), findsNothing);
      expect(find.text('기록을 불러오지 못했어요'), findsNothing);
    });
  });

  group('회고 진입 (#187)', () {
    testWidgets('서버에 있는 산책을 누르면 회고 화면이 열린다', (t) async {
      await _pump(t, _Repo(items: [walkOf()]));

      await t.tap(find.text('아침 산책'));
      await t.pumpAndSettle();

      expect(find.text('산책 회고'), findsOneWidget);
    });

    testWidgets('카드가 두 가지를 할 수 있다고 말한다', (t) async {
      await _pump(t, _Repo(items: [walkOf()]));
      expect(find.text('눌러서 회고 쓰기 · 길게 눌러 지우기'), findsOneWidget);
    });

    testWidgets('거절된 것은 누를 곳이 없다 — 서버에 행이 없어 고칠 대상이 없다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(), '메모가 너무 길어요');
      await _pump(t, _Repo());

      await t.tap(find.text('아침 산책'));
      await t.pumpAndSettle();

      expect(find.text('산책 회고'), findsNothing);
      // 지우기만 할 수 있다고 말한다.
      expect(find.text('길게 눌러 지우기'), findsOneWidget);
    });
  });

  group('전송 대기 중인 것', () {
    testWidgets('지울 수 없다 — 올라가는 중에 지우면 서버에만 남는다', (t) async {
      final outbox = await WalkOutbox.open();
      await outbox.put(draftOf());

      await _pump(t, _Repo());

      expect(find.text('전송 대기'), findsOneWidget);
      expect(find.textContaining('길게 눌러 지우기'), findsNothing);
    });
  });

  group('WalkFeed 가 거절 큐를 나른다', () {
    test('load() 결과에 rejected 가 들어 있다', () async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(key: 'r1'), '메모가 너무 길어요');

      final data = await WalkFeed(repository: _Repo()).load();

      expect(data.rejected.single.clientWalkId, 'r1');
      expect(data.rejected.single.lastError, '메모가 너무 길어요');
    });

    test('거절된 것만 있어도 hasAnything 이 참이다', () async {
      final outbox = await WalkOutbox.open();
      await outbox.reject(draftOf(), '메모가 너무 길어요');

      final data = await WalkFeed(repository: _Repo()).load();

      expect(data.hasAnything, isTrue,
          reason: '거짓이면 빈 화면 문구 아래에 거절 카드가 놓인다');
    });
  });

  // "…" 메뉴 — 길게 누르기는 눌러 보기 전엔 있는지 모른다 (#327).
  group('카드의 … 메뉴', () {
    testWidgets('… → 지우기 → 확인부터 묻는다', (t) async {
      final repo = _Repo(items: [walkOf()]);
      await _pump(t, repo);
      await t.tap(find.byIcon(Icons.more_horiz_rounded));
      await t.pumpAndSettle();
      expect(find.text('지우기'), findsOneWidget);
      expect(find.text('회고 쓰기'), findsOneWidget, reason: '서버에 있는 기록은 회고도 된다');
      await t.tap(find.text('지우기'));
      await t.pumpAndSettle();
      expect(find.text('이 기록을 지울까요?'), findsOneWidget);
      expect(repo.deleted, isEmpty, reason: '묻기 전에 지우면 안 된다');
    });

    testWidgets('거짓 플랜 문구가 없다 — 유료 플랜은 없다', (t) async {
      final repo = _Repo(items: [walkOf()]);
      await _pump(t, repo);
      expect(find.textContaining('무료 플랜'), findsNothing);
    });
  });

}

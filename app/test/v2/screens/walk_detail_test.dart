// 산책 회고를 나중에 고칠 수 있는가 — 이슈 #187.
//
// 메모는 저장 시점의 한 번이 전부였다. 산책이 끝난 직후에 쓰는 글과 나중에 돌아보며
// 쓰는 글은 다른데, 잘못 쓰면 지우고 다시 만드는 수밖에 없었다.
//
// ## 여기서 재는 것
//
//  1. 안 바뀌었으면 '저장' 이 눌리지 않는가. 항상 켜 두면 "눌렀는데 아무 일도 안 난다".
//  2. 빈 글로 저장하면 지워지는가 — 서버가 null 로 눕혀 돌려주고 화면이 그걸 받는가.
//  3. 실패했을 때 **사용자가 쓴 글을 되돌리지 않는가.** 되돌리면 그게 더 나쁘다.
//  4. 목록에 알리는가. 안 알리면 뒤로 갔을 때 옛 글이 남는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/walk_feed.dart';
import 'package:heat_trip_flutter/v2/data/walk_repository.dart';
import 'package:heat_trip_flutter/v2/screens/walk_detail_screen.dart';

class _Repo implements WalkRepository {
  _Repo({this.fails});

  WalkFailure? fails;
  final List<String> sent = [];

  @override
  Future<ServerWalk> rewriteMemo(int walkId, String memo) async {
    sent.add(memo);
    final f = fails;
    if (f != null) throw f;
    return ServerWalk(
      id: walkId,
      dogId: 1,
      clientWalkId: 'ck-$walkId',
      startedAt: DateTime(2026, 9, 1, 9),
      distanceM: 2400,
      durationS: 1800,
      // 서버는 빈 글을 null 로 눕혀 돌려준다.
      memo: memo.trim().isEmpty ? null : memo,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} 은 이 테스트가 안 쓴다');
}

Future<_Repo> _pump(WidgetTester t, {String memo = '처음 쓴 글', WalkFailure? fails}) async {
  final repo = _Repo(fails: fails);
  await t.pumpWidget(MaterialApp(
    home: WalkDetailScreen(
      walkId: 7,
      startedAt: DateTime(2026, 9, 1, 9),
      km: 2.4,
      minutes: 30,
      initialMemo: memo,
      repository: repo,
    ),
  ));
  await t.pumpAndSettle();
  return repo;
}

/// '저장' 버튼이 눌리는가 — `onPressed` 가 null 이면 꺼진 것이다.
bool _saveEnabled(WidgetTester t) {
  final b = t.widget<TextButton>(find.ancestor(
    of: find.text('저장'),
    matching: find.byType(TextButton),
  ));
  return b.onPressed != null;
}

void main() {
  tearDown(() => walkFeedRevision.value = 0);

  group('저장 버튼', () {
    testWidgets('안 바꿨으면 꺼져 있다', (t) async {
      await _pump(t);
      expect(_saveEnabled(t), isFalse,
          reason: '항상 켜 두면 "눌렀는데 아무 일도 안 난다" 가 된다');
    });

    testWidgets('한 글자만 바꿔도 켜진다', (t) async {
      await _pump(t);
      await t.enterText(find.byType(TextField), '처음 쓴 글!');
      await t.pump();
      expect(_saveEnabled(t), isTrue);
    });

    testWidgets('저장하고 나면 다시 꺼진다', (t) async {
      await _pump(t);
      await t.enterText(find.byType(TextField), '다시 쓴 글');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(_saveEnabled(t), isFalse);
    });
  });

  group('서버로 보내는 것', () {
    testWidgets('사용자가 쓴 그대로 보낸다', (t) async {
      final repo = await _pump(t);
      await t.enterText(find.byType(TextField), '오늘은 비가 왔다');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(repo.sent, ['오늘은 비가 왔다']);
    });

    testWidgets('빈 글도 보낸다 — "다 지웠다" 는 정상 요청이다', (t) async {
      final repo = await _pump(t);
      await t.enterText(find.byType(TextField), '');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(repo.sent, ['']);
      // 서버가 눕힌 값을 받아 저장 버튼이 꺼진다. 앱이 짐작하면 영원히 켜져 있다.
      expect(_saveEnabled(t), isFalse);
    });

    testWidgets('목록에 알린다 — 안 알리면 뒤로 갔을 때 옛 글이 남는다', (t) async {
      await _pump(t);
      final before = walkFeedRevision.value;

      await t.enterText(find.byType(TextField), '바뀐 글');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(walkFeedRevision.value, greaterThan(before));
    });
  });

  group('실패했을 때', () {
    testWidgets('사용자가 쓴 글을 되돌리지 않는다', (t) async {
      await _pump(t, fails: const WalkFailure(WalkFailureKind.network));
      await t.enterText(find.byType(TextField), '공들여 쓴 글');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(find.text('공들여 쓴 글'), findsOneWidget,
          reason: '실패했다고 사용자가 쓴 것을 지우면 그게 더 나쁘다');
      expect(_saveEnabled(t), isTrue, reason: '다시 시도할 수 있어야 한다');
    });

    testWidgets('사유를 말한다 — 조용히 성공한 척하지 않는다', (t) async {
      await _pump(t, fails: const WalkFailure(WalkFailureKind.network));
      await t.enterText(find.byType(TextField), '글');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(find.text(WalkFailureKind.network.message), findsOneWidget);
      expect(find.text('기록했어요'), findsNothing);
    });

    testWidgets('목록에 알리지 않는다 — 안 바뀐 것을 바뀌었다고 하면 안 된다', (t) async {
      await _pump(t, fails: const WalkFailure(WalkFailureKind.network));
      final before = walkFeedRevision.value;

      await t.enterText(find.byType(TextField), '글');
      await t.pump();
      await t.tap(find.text('저장'));
      await t.pumpAndSettle();

      expect(walkFeedRevision.value, before);
    });
  });

  group('글 길이', () {
    testWidgets('서버와 같은 상한을 건다', (t) async {
      await _pump(t);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, WalkRepository.maxMemoLength);
    });
  });
}

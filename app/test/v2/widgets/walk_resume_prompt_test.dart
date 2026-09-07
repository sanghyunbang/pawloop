// 끊긴 산책 — 묻고, 이어서 기록하거나 지운다 (#335).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/data/walk_in_progress.dart';
import 'package:heat_trip_flutter/v2/widgets/walk_resume_prompt.dart';

const _store = WalkInProgressStore();

WalkInProgress _walk() => WalkInProgress(
      startedAt: DateTime(2026, 9, 7, 15, 41),
      seconds: 720,
      distanceM: 320,
      path: const [
        [127.0410, 37.5445],
      ],
      pathT: const [0],
      savedAt: DateTime.now(),
    );

/// 버튼 하나 — 누르면 [WalkResumePrompt.offer] 를 부르고 결과를 담는다.
Future<ValueNotifier<WalkInProgress?>> _pumpOffer(WidgetTester t) async {
  final result = ValueNotifier<WalkInProgress?>(null);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result.value = await WalkResumePrompt.offer(ctx, store: _store),
          child: const Text('offer'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('offer'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthState.signInForTest(const AuthUser(id: 1, nickname: 'walker'));
  });
  tearDown(AuthState.resetForTest);

  test('summary — 거리·분·시작 시각', () {
    expect(WalkResumePrompt.summary(_walk()), '지난 산책이 저장되지 않은 채 끝났어요.\n0.32km · 12분 · 15:41 시작');
  });

  testWidgets('스냅숏이 없으면 아무것도 묻지 않는다', (t) async {
    final result = await _pumpOffer(t);

    expect(find.text('이어서 기록할까요?'), findsNothing);
    expect(result.value, isNull);
  });

  testWidgets('"이어서 기록" 이면 스냅숏을 돌려주고 남겨 둔다', (t) async {
    await _store.save(_walk());
    final result = await _pumpOffer(t);

    expect(find.text('이어서 기록할까요?'), findsOneWidget);
    expect(find.textContaining('0.32km · 12분'), findsOneWidget);

    await t.tap(find.text('이어서 기록'));
    await t.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.distanceM, 320);
  });

  testWidgets('"지우기" 면 지우고 null — 다음에 또 묻지 않는다', (t) async {
    await _store.save(_walk());
    final result = await _pumpOffer(t);

    await t.tap(find.text('지우기'));
    await t.pumpAndSettle();

    expect(result.value, isNull);
    expect(await _store.load(), isNull);
  });

  testWidgets('홈 게이트 — 로그인 상태면 첫 프레임 뒤에 묻고, 이어서 기록이면 추적 화면을 연다', (t) async {
    await _store.save(_walk());
    WalkInProgress? opened;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          const Text('home'),
          WalkResumeGate(store: _store, openTracking: (_, w) async => opened = w),
        ]),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('이어서 기록할까요?'), findsOneWidget);
    await t.tap(find.text('이어서 기록'));
    await t.pumpAndSettle();

    expect(opened, isNotNull);
    expect(opened!.seconds, 720);
  });

  testWidgets('홈 게이트 — 게스트에게는 묻지 않고, 스냅숏도 지우지 않는다', (t) async {
    await _store.save(_walk());
    AuthState.resetForTest();
    AuthState.status.value = AuthStatus.unauthenticated;
    var opened = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WalkResumeGate(store: _store, openTracking: (_, __) async => opened++),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('이어서 기록할까요?'), findsNothing);
    expect(opened, 0);
    expect(await _store.load(), isNotNull, reason: '다시 로그인하면 그때 묻는다');
  });
}

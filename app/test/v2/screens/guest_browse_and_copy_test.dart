// 게스트가 보는 두 자리 — 문구와 "그냥 둘러보기" 의 목적지.
//
// 둘 다 실기기 점검에서 잡았다.
//
// ## 문구가 제공자를 세고 있었다
//
// 게스트 프로필이 "카카오나 Google 로 시작하고…" 라고 적고 있었다. 로그인 제공자는 셋인데
// (카카오·구글·Apple, #544 가 Apple 을 모든 플랫폼에서 보이게 했다) 둘만 적혀 있었고,
// 정작 그 화면의 버튼은 `로그인 / 회원가입` 하나다. **제공자가 늘거나 줄 때마다 고쳐야 하는
// 문장은 반드시 낡는다** — 실제로 낡아 있었다. 그래서 세지 않는 문장으로 바꾸고, 이 검사가
// 다시 세는 것을 막는다.
//
// 처음엔 소스를 정규식으로 긁었는데 **가짜 초록이었다**. `guest\s*\?\s*'…'` 가 첫 번째
// `guest ?` 인 제목 줄에 붙었고, 그 줄엔 제공자 이름이 원래 없어서 문구를 옛것으로 되돌려도
// 통과했다. 게다가 고친 문구는 `guest` 와 `?` 사이에 주석이 끼어 정규식이 닿지도 않았다.
// 그래서 **화면을 세우고 눈에 보이는 글자를 전부 훑는다** — 어느 줄인지 맞힐 필요가 없다.
//
// ## 둘러보기가 둘러보기를 안 시켰다
//
// `canPop()` 이면 `pop()` 했다. 프로필에서 열었으면 프로필로 돌아간다는 뜻인데, 게스트
// 프로필은 "로그인하세요" 말고 할 것이 없는 화면이다. **둘러보라고 적어 놓고 로그인하라는
// 화면으로 되돌리니 고리가 됐다.**
//
// 여기서는 라우터를 세워 **목적지**를 잰다 — 버튼이 눌리는지가 아니라 어디로 가는지가 요점이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heat_trip_flutter/v2/data/auth_state.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/screens/login_screen.dart';
import 'package:heat_trip_flutter/v2/screens/me_screen.dart';

/// 로그인 제공자 이름. 게스트 프로필에 이것들이 **보이면** 빨간불이다.
const _providerNames = ['카카오', 'Google', '구글', 'Apple', '애플'];

/// 지금 화면에 실제로 그려진 글자 전부. `Text.data` 와 `Text.rich` 양쪽을 본다.
List<String> _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  group('그냥 둘러보기', () {
    testWidgets('프로필에서 열었어도 홈으로 간다 — 온 곳으로 되돌리지 않는다', (t) async {
      final visited = <String>[];
      final router = GoRouter(
        initialLocation: '/me',
        routes: [
          GoRoute(
            path: '/me',
            builder: (c, s) {
              visited.add('/me');
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    // 실기기와 같은 길 — 프로필이 로그인 화면을 **얹는다**.
                    onPressed: () => Navigator.of(c)
                        .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text('로그인 / 회원가입'),
                  ),
                ),
              );
            },
          ),
          GoRoute(
              path: '/home',
              builder: (c, s) {
                visited.add('/home');
                return const Scaffold(body: Text('홈이다'));
              }),
        ],
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.tap(find.text('로그인 / 회원가입'));
      await t.pumpAndSettle();
      expect(find.text('그냥 둘러보기'), findsOneWidget);

      await t.tap(find.text('그냥 둘러보기'));
      await t.pumpAndSettle();

      expect(find.text('홈이다'), findsOneWidget,
          reason: '둘러보라고 해놓고 온 곳(프로필)으로 되돌리면 고리가 된다');
      expect(visited.last, '/home');
    });
  });

  group('게스트 프로필 안내 문구', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      kMyDog.value = null;
    });
    tearDown(AuthState.resetForTest);

    testWidgets('로그인 제공자를 세지 않는다 — 세는 문장은 반드시 낡는다', (t) async {
      AuthState.resetForTest();
      AuthState.status.value = AuthStatus.unauthenticated;

      await t.pumpWidget(const MaterialApp(home: MeScreen()));
      await t.pumpAndSettle();

      final shown = _visibleText(t);
      // 화면을 제대로 세웠는지부터 못 박는다 — 빈 목록을 훑으면 무엇을 금지하든 통과한다.
      expect(shown, contains('로그인 / 회원가입'),
          reason: '게스트 빈 프로필이 안 떴다. 아래 검사는 이 화면을 보고 있어야 의미가 있다');

      for (final name in _providerNames) {
        final offenders = shown.where((s) => s.contains(name)).toList();
        expect(offenders, isEmpty, reason: '''
게스트 프로필이 "$name" 을 세고 있다: $offenders
제공자는 셋(카카오·구글·Apple)이고 버튼은 하나다 — 세는 문장은 제공자가 바뀔 때마다 낡는다.
실제로 "카카오나 Google" 로 낡아 있었다.''');
      }
    });
  });
}

// lib/v2/screens/start_walk.dart
//
// 산책을 시작하는 유일한 문 — 이슈 #145.
//
// ## 왜 헬퍼가 필요한가
//
// 산책 시작 버튼이 둘이다(`today_screen` 의 "산책 시작", `main_shell` 의 가운데 + 버튼).
// 둘 다 `MaterialPageRoute` 로 바로 밀어 넣고 있었다.
//
// 그래서 **미로그인으로도 산책이 시작된다.** 30분을 걷고 저장을 누른 다음에야
// "로그인해 주세요" 를 만난다. 그때 기록은 초안 큐에 남지만, 사용자 입장에서는
// 걷고 나서 벽을 만난 것이다.
//
// `GoRouter` 의 보호 규칙(`/record/create`)이 이걸 막아 줄 것 같지만 **막지 못한다** —
// 두 진입점 모두 라우터를 안 지나고 `MaterialPageRoute` 로 직접 연다. 죽은 규칙이다.
//
// 그래서 두 자리가 같은 헬퍼 하나를 지나게 한다. 세 번째 버튼이 생겨도 여기를 부르면 된다.
library;

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import 'login_screen.dart';
import 'walk_tracking_screen.dart';

/// 산책 트래킹을 연다. **미로그인이면 로그인부터 안내한다.**
///
/// 로그인을 마치고 돌아오면 그때 트래킹을 연다 — 사용자가 버튼을 두 번 누르게 하지
/// 않는다.
Future<void> startWalk(BuildContext context) async {
  if (!AuthState.isAuthenticated) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Text('로그인하면 산책 기록이 남아요'),
        duration: Duration(milliseconds: 1600),
      ),
    );
    await navigator.push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // 로그인 화면에서 그냥 돌아왔을 수 있다. 그러면 시작하지 않는다.
    if (!AuthState.isAuthenticated) return;
    if (!context.mounted) return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const WalkTrackingScreen()),
  );
}

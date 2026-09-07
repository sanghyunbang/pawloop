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
import '../data/walk_in_progress.dart';
import '../data/walk_safety_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/walk_resume_prompt.dart';
import 'location_priming_sheet.dart';
import 'walk_tracking_screen.dart';

/// 산책 트래킹을 연다. **미로그인이면 로그인부터 안내한다.**
///
/// 로그인을 마치고 돌아오면 그때 트래킹을 연다 — 사용자가 버튼을 두 번 누르게 하지
/// 않는다.
///
/// 로그인 뒤, 위치 권한이 없으면 **앱의 사전 안내 시트**가 먼저다(#325). OS 대화상자는
/// 추적 화면([WalkTrackingScreen] → `LocationService.locate`)이 부르므로, "허용하기" 전에는
/// 그 화면을 열지 않는다. [openTracking] 은 테스트가 추적 화면 대신 꽂는 자리다.
///
/// 끊긴 산책의 스냅숏이 남아 있으면 새로 시작하기 전에 묻는다(#335). "이어서 기록" 이면 그
/// 스냅숏으로 추적 화면을 연다 — 권한 시트는 건너뛴다(권한이 사라졌으면 추적 화면이 말한다).
Future<void> startWalk(
  BuildContext context, {
  Future<void> Function(BuildContext context, WalkInProgress? resume)? openTracking,
  WalkInProgressStore resumeStore = const WalkInProgressStore(),
  DateTime Function()? now,
}) async {
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
    // 로그인 화면은 **pop 을 먼저 하고** 그 뒤에 completeLogin() 을 부른다. 여기서
    // 바로 물으면 성공한 로그인도 아직 false 라, 걸으러 온 사람이 아무것도 못 하고
    // 서 있게 된다. `writePost` 도 같은 자리를 지난다.
    await AuthState.settle();

    // 그냥 돌아왔을 수 있다. 그러면 시작하지 않는다.
    if (!AuthState.isAuthenticated) return;
    if (!context.mounted) return;
  }

  if (!context.mounted) return;
  final leftover = await WalkResumePrompt.offer(context, store: resumeStore);
  if (!context.mounted) return;
  if (leftover != null) {
    await (openTracking ?? _openTracking)(context, leftover);
    return;
  }
  final state = await LocationPriming.stateFor();
  if (!context.mounted) return;
  if (state != null) {
    final answer = await LocationPrimingSheet.show(context, state);
    if (!context.mounted) return;
    switch (answer) {
      case LocationPrimingAnswer.later:
        return;
      case LocationPrimingAnswer.openSettings:
        await LocationPriming.openSettings();
        return;
      case LocationPrimingAnswer.allow:
        // 다음에 또 거부 상태면 "설정에서 켜기" 길을 보여 준다.
        await LocationPriming.markAsked();
    }
  }
  if (!context.mounted) return;
  if (!await _confirmIfUnsafe(context, now: (now ?? DateTime.now)())) return;
  if (!context.mounted) return;
  await (openTracking ?? _openTracking)(context, null);
}

/// "피하세요" 판정이 살아 있으면(30분 안) 한 번 묻는다 — 막지 않는다(#336). 홈 카드가 받아 둔 값을
/// 쓰고, 없으면 묻지 않는다: 산책 시작을 네트워크에 기다리게 하지 않는다.
Future<bool> _confirmIfUnsafe(BuildContext context, {required DateTime now}) async {
  final verdict = WalkSafetyStore.latest.value;
  if (verdict == null || !verdict.shouldAskBeforeWalk || !WalkSafetyStore.isFresh(now)) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFFFCFAFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('지금은 피하는 게 좋아요',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
      content: Text('${verdict.headline}\n${verdict.reasons.join(' · ')}',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: const Text('나중에', style: TextStyle(color: T.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: const Text('그래도 시작', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE07A4E))),
        ),
      ],
    ),
  );
  return go ?? false;
}

Future<void> _openTracking(BuildContext context, WalkInProgress? resume) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WalkTrackingScreen(resume: resume)),
    );

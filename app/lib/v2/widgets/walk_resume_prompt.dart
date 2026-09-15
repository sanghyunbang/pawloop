// 끊긴 산책을 이어서 기록할지 묻는다 (#335).
//
// 앱이 죽었다 살아났을 때(홈이 뜰 때)와 새 산책을 시작하려 할 때, 기기에 남은 스냅숏이 있으면
// 한 번 묻는다. 묻지 않고 이어 붙이면 어제의 산책이 오늘 산책이 되고, 묻지 않고 버리면 30분이
// 사라진다.
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/walk_in_progress.dart';
import '../domain/walk_labels.dart';
import '../theme/app_tokens.dart';

enum WalkResumeChoice { resume, discard }

class WalkResumePrompt {
  WalkResumePrompt._();

  /// 스냅숏이 있으면 묻고, "이어서 기록" 이면 그 스냅숏을 돌려준다. "지우기" 면 지우고 `null`,
  /// 그냥 닫으면 남겨 두고 `null`(다음에 또 묻는다). 스냅숏이 없으면 아무것도 띄우지 않는다.
  static Future<WalkInProgress?> offer(
    BuildContext context, {
    WalkInProgressStore store = const WalkInProgressStore(),
  }) async {
    final walk = await store.load();
    if (walk == null || !context.mounted) return null;
    final choice = await showDialog<WalkResumeChoice>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: T.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '이어서 기록할까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary),
        ),
        content: Text(
          summary(walk),
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: T.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, WalkResumeChoice.discard),
            child: const Text('지우기', style: TextStyle(color: T.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, WalkResumeChoice.resume),
            child: const Text(
              '이어서 기록',
              style: TextStyle(fontWeight: FontWeight.w800, color: T.warmText),
            ),
          ),
        ],
      ),
    );
    switch (choice) {
      case WalkResumeChoice.resume:
        return walk;
      case WalkResumeChoice.discard:
        await store.clear();
        return null;
      case null:
        return null;
    }
  }

  /// "지난 산책이 저장되지 않은 채 끝났어요. 0.32km · 12분 · 15:41 시작"
  ///
  /// 1분이 안 되면 `44초` 다(#537) — 여기서 `0분` 이면 "안 걸었다" 로 읽혀 이어걷기를 안 누른다.
  static String summary(WalkInProgress walk) {
    final at = walk.startedAt.toLocal();
    final hh = '${at.hour}'.padLeft(2, '0');
    final mm = '${at.minute}'.padLeft(2, '0');
    return '지난 산책이 저장되지 않은 채 끝났어요.\n'
        '${walk.km.toStringAsFixed(2)}km · ${walkTimeLabel(walk.seconds)} · $hh:$mm 시작';
  }
}

/// 홈 셸에 한 번 끼워 두면, 첫 프레임 뒤에 스냅숏을 확인해 묻고 추적 화면을 연다.
/// 그리는 것은 없다(`SizedBox.shrink`).
class WalkResumeGate extends StatefulWidget {
  const WalkResumeGate({
    super.key,
    this.store = const WalkInProgressStore(),
    required this.openTracking,
  });

  final WalkInProgressStore store;

  /// 이어서 기록할 스냅숏으로 추적 화면을 연다. 테스트가 세는 자리.
  final Future<void> Function(BuildContext context, WalkInProgress walk) openTracking;

  @override
  State<WalkResumeGate> createState() => _WalkResumeGateState();
}

class _WalkResumeGateState extends State<WalkResumeGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    // 산책은 로그인한 사람만 시작할 수 있었다 — 게스트에게 남의 스냅숏을 묻지 않는다. 지우지도
    // 않는다: 그 사람이 다시 로그인하면 다음 홈에서 묻는다.
    if (!AuthState.isAuthenticated) return;
    final walk = await WalkResumePrompt.offer(context, store: widget.store);
    if (walk == null || !mounted) return;
    await widget.openTracking(context, walk);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

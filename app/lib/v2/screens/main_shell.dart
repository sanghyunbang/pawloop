import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'today_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'chat_list_screen.dart';
import 'walk_tracking_screen.dart';

/// 루트 탭 상태. 푸시된 화면(result 등)에서도 탭을 바꿀 수 있게 전역 보관.
class RootTab {
  static final ValueNotifier<int> index = ValueNotifier(0);
  static final ValueNotifier<String> exploreView = ValueNotifier('list');

  /// 모든 푸시 라우트를 닫고 해당 탭으로 이동. (result의 "더 둘러보기" 등)
  static void go(BuildContext context, int i, {String? exView}) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (exView != null) exploreView.value = exView;
    index.value = i;
  }
}

/// 메인 네비게이션 셸 — 오늘/탐색/커뮤니티/흐름 탭 + 가운데 기록(+) 버튼.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: ValueListenableBuilder<int>(
        valueListenable: RootTab.index,
        builder: (_, i, __) {
          final Widget screen;
          switch (i) {
            case 1:
              screen = ValueListenableBuilder<String>(
                valueListenable: RootTab.exploreView,
                builder: (_, v, __) => ExploreScreen(key: ValueKey(v), initialView: v),
              );
              break;
            case 2:
              screen = const FeedScreen();
              break;
            case 3:
              screen = const ChatListScreen();
              break;
            default:
              screen = const TodayScreen();
          }
          // 떠 있는 바텀네비를 본문 위에 오버레이(배경 끊김 없이, 항상 보임).
          return Stack(children: [
            Positioned.fill(child: screen),
            const Align(alignment: Alignment.bottomCenter, child: _ShellNav()),
          ]);
        },
      ),
    );
  }
}

class _ShellNav extends StatelessWidget {
  const _ShellNav();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8E7BFF);
    return ValueListenableBuilder<int>(
      valueListenable: RootTab.index,
      builder: (_, idx, __) {
        Widget item(IconData icon, String label, int i) => Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => RootTab.index.value = i,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 23, color: idx == i ? accent : T.textMuted),
                  const SizedBox(height: 3),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: idx == i ? FontWeight.w800 : FontWeight.w500,
                          color: idx == i ? accent : T.textMuted)),
                ]),
              ),
            );
        final bottom = MediaQuery.of(context).padding.bottom;
        return SizedBox(
          height: bottom + 100,
          child: Stack(clipBehavior: Clip.none, children: [
            // 떠 있는 글래스 알약
            Positioned(
              left: 16, right: 16, bottom: bottom + 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    height: 66,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xAAFFFFFF),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xC7FFFFFF)),
                      boxShadow: const [BoxShadow(color: Color(0x2E5A4690), blurRadius: 30, offset: Offset(0, 12))],
                    ),
                    child: Row(children: [
                      item(Icons.home_rounded, '홈', 0),
                      item(Icons.map_outlined, '지도', 1),
                      const SizedBox(width: 56),
                      item(Icons.forum_outlined, '커뮤니티', 2),
                      item(Icons.chat_bubble_outline, '채팅', 3),
                    ]),
                  ),
                ),
              ),
            ),
            // 솟은 가운데 기록(+) 버튼
            Positioned(
              left: 0, right: 0, bottom: bottom + 38,
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalkTrackingScreen()),
                  ),
                  child: Container(
                    width: 58, height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
                      border: Border.all(color: const Color(0xA6FFFFFF), width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x80D89BFF), blurRadius: 22, offset: Offset(0, 10))],
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 25),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

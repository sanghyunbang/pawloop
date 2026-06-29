import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'today_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'insight_screen.dart';
import 'myrecords_screen.dart';

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
          switch (i) {
            case 1:
              return ValueListenableBuilder<String>(
                valueListenable: RootTab.exploreView,
                builder: (_, v, __) => ExploreScreen(key: ValueKey(v), initialView: v),
              );
            case 2:
              return const FeedScreen();
            case 3:
              return const InsightScreen();
            default:
              return const TodayScreen();
          }
        },
      ),
      bottomNavigationBar: const _ShellNav(),
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
        return Container(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 8 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Color(0xE6FFFFFF),
            border: Border(top: BorderSide(color: Color(0x22785AA0))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            item(Icons.wb_sunny_outlined, '오늘', 0),
            item(Icons.explore_outlined, '탐색', 1),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyRecordsScreen()),
                  ),
                  child: Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9FCF), Color(0xFFFF8FA8)]),
                      boxShadow: [BoxShadow(color: Color(0x4DFF8FA8), blurRadius: 14, offset: Offset(0, 6))],
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 24),
                  ),
                ),
              ]),
            ),
            item(Icons.chat_bubble_outline, '커뮤니티', 2),
            item(Icons.show_chart, '흐름', 3),
          ]),
        );
      },
    );
  }
}

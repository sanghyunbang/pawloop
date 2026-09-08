import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'today_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'chat_list_screen.dart';
import 'start_walk.dart';
import 'walk_tracking_screen.dart';
import '../data/walk_in_progress.dart';
import '../widgets/walk_resume_prompt.dart';
import '../widgets/pet_loader.dart';

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
  /// 끊긴 산책 스냅숏 저장소. 테스트가 갈아 끼운다(#335).
  final WalkInProgressStore resumeStore;

  const MainShell({super.key, this.resumeStore = const WalkInProgressStore()});

  @override
  Widget build(BuildContext context) {
    // 반려동물 목록을 서버와 맞추는 책임은 여기 하나다 (#159). 화면마다 initState 에서
    // 부르면 한 곳을 빠뜨리는 날이 오고, 그 화면만 영원히 빈 목록을 본다.
    return PetLoader(
      child: Scaffold(
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
            // 앱이 죽었다 살아났을 때 끊긴 산책을 이어 갈지 묻는다(#335). 그리는 것은 없다.
            WalkResumeGate(
              store: resumeStore,
              openTracking: (ctx, walk) => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => WalkTrackingScreen(resume: walk)),
              ),
            ),
          ]);
        },
      ),
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
                  // 탭 라벨의 배율만 1.3 에서 멈춘다 — 이슈 #396.
                  //
                  // 네 칸이 한 알약을 나눠 쓰므로 360dp 에서 한 칸이 59dp 다. 2.0배의
                  // "커뮤니티" 는 거기 안 들어가 두 줄로 접히고, 알약 높이 66 을 24px
                  // 넘겼다. 자르면 "커뮤…" 가 되어 무엇을 누르는지 알 수 없다.
                  //
                  // 본문은 배율을 그대로 따른다 — 여기만 멈춘다. 화면을 읽는 글자와
                  // 길을 찾는 표지판은 다르고, Material 의 NavigationBar 도 같은 이유로
                  // 라벨 배율을 제한한다.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: idx == i ? FontWeight.w800 : FontWeight.w500,
                            color: idx == i ? accent : T.textMuted)),
                  ),
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
                    // 못 박지 않는다 — 1.3배까지 라벨이 자라면 알약도 함께 자란다(#396).
                    constraints: const BoxConstraints(minHeight: 66),
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
                  // today_screen 의 "산책 시작" 과 같은 문을 지난다.
                  onTap: () => startWalk(context),
                  child: Container(
                    width: 58, height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9E7D), Color(0xFFD89BFF)]),
                      border: Border.all(color: const Color(0xA6FFFFFF), width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x80D89BFF), blurRadius: 22, offset: Offset(0, 10))],
                    ),
                    child: const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 26),
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

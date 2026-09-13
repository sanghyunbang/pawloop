import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'today_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'chat_list_screen.dart';
import 'schedule_screen.dart';
import '../data/local_notification_sink.dart';
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

/// 메인 네비게이션 셸 — 홈 · 지도 · 일정 · 커뮤니티 · 채팅. 다섯 칸 같은 폭(#446). 산책은 홈의 "산책 시작" 이 맡는다.
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
      backgroundColor: T.bgTop,
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
              // 알림 싱크는 여기서 물려 준다 — 화면이 스스로 만들면 위젯 테스트가 그것을
              // 갈아끼울 수 없고, 진짜는 테스트 바인딩에 채널이 없어 던진다(#420).
              screen = ScheduleScreen(reminderSink: LocalNotificationSink());
              break;
            case 3:
              screen = const FeedScreen();
              break;
            case 4:
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

  /// 채도를 1.5배 올리는 색 행렬. iOS 의 재질이 뒤 색을 살짝 진하게 비추는 것을 흉내 낸다 —
  /// 블러만 하면 뒤가 뿌옇게 회색이 되고, 채도를 올려야 "유리 너머" 로 읽힌다(#446).
  static const List<double> _saturate = <double>[
    1.3935, -0.3575, -0.0360, 0, 0,
    -0.1065, 1.1425, -0.0360, 0, 0,
    -0.1065, -0.3575, 1.4640, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RootTab.index,
      builder: (_, idx, __) {
        // 탭 라벨의 배율만 1.3 에서 멈춘다 — 이슈 #396.
        //
        // 다섯 칸이 한 알약을 나눠 쓰므로 360dp 에서 한 칸이 60dp 안팎이다. 2.0배의
        // "커뮤니티" 는 거기 안 들어가 두 줄로 접히고 알약을 넘긴다. 자르면 "커뮤…" 가
        // 되어 무엇을 누르는지 알 수 없다. 본문은 배율을 그대로 따른다 — 여기만 멈춘다.
        // 화면을 읽는 글자와 길을 찾는 표지판은 다르고, Material 의 NavigationBar 도
        // 같은 이유로 라벨 배율을 제한한다.
        Widget label(String text, bool on) => MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                      color: on ? T.accent : T.textMuted)),
            );

        Widget item(IconData icon, String text, int i) => Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => RootTab.index.value = i,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 23, color: idx == i ? T.accent : T.textMuted),
                  const SizedBox(height: 3),
                  label(text, idx == i),
                ]),
              ),
            );

        // 산책은 바에 없다 — 사장님 결정(2026-09-14, #446): 일정 탭은 필수라 가운데 산책까지
        // 두면 여섯이 되고, Apple·Material 둘 다 다섯이 한계다. 산책은 홈의 "산책 시작" 이
        // 맡는다. 다섯 칸 전부 Expanded 라 좌우가 대칭이고 가운데가 일정이다.
        final bottom = MediaQuery.of(context).padding.bottom;
        // 떠 있는 유리 알약 — 유리는 이 이동 층에만 쓴다. 카드에는 안 쓴다(HIG "재질").
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.compose(
                outer: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                inner: const ColorFilter.matrix(_saturate),
              ),
              child: Container(
                // 못 박지 않는다 — 1.3배까지 라벨이 자라면 알약도 함께 자란다(#396).
                constraints: const BoxConstraints(minHeight: 66),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                decoration: BoxDecoration(
                  // 흰색 88% — 흰 바탕 위에서는 외곽선이 알약을 만들고, 스크롤 밑의
                  // 콘텐츠가 살짝 비친다(유리).
                  color: const Color(0xE0FFFFFF),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: T.cardBorder),
                  boxShadow: const [
                    BoxShadow(color: T.barShadow, blurRadius: 30, offset: Offset(0, 12)),
                  ],
                ),
                // 다섯 칸 전부 Expanded — 같은 폭이라 좌우가 대칭이다.
                child: Row(children: [
                  item(Icons.home_rounded, '홈', 0),
                  item(Icons.map_outlined, '지도', 1),
                  item(Icons.event_note_outlined, '일정', 2),
                  item(Icons.forum_outlined, '커뮤니티', 3),
                  item(Icons.chat_bubble_outline, '채팅', 4),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

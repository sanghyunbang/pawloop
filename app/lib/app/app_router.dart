import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/navigator_keys.dart';
import 'package:heat_trip_flutter/core/widgets/layout/main_nav_shell.dart';
import 'package:heat_trip_flutter/features/bookmark/bookmark_routes.dart';
import 'package:heat_trip_flutter/v2/screens/main_shell.dart';

// tabs
import 'package:heat_trip_flutter/features/start/start_routes.dart';
import 'package:heat_trip_flutter/features/auth/auth_routes.dart';
import 'package:heat_trip_flutter/features/explore/explore_routes.dart';
import 'package:heat_trip_flutter/features/record/record_routes.dart';
import 'package:heat_trip_flutter/features/journey/journey_routes.dart';
import 'package:heat_trip_flutter/features/profile/profile_routes.dart';

import 'package:heat_trip_flutter/features/foryou_v2/routes.dart';
import 'package:heat_trip_flutter/features/emotion_map/emotion_map_routes.dart';

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  // v2 디자인을 정식 진입으로 승격. (구 /start 셸은 아래에 보존 — 로그인/구화면 참조용)
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const MainShell()),
    ...startRoutes,
    ...authRoutes,
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => MainNavShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: buildExploreRoutes()), // 0
        StatefulShellBranch(routes: recordRoutes), // 1 (Schedule, 네비 강등)
        StatefulShellBranch(routes: forYouV2Routes), // 2 오늘
        StatefulShellBranch(routes: journeyRoutes), // 3 피드
        StatefulShellBranch(
          routes: [...profileRoutes, ...bookmarkRoutes],
        ), // 4 나
        StatefulShellBranch(routes: emotionMapRoutes), // 5 감정지도
      ],
    ),
  ],
);

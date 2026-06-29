import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'presentation/discover_screen.dart';
import 'presentation/emotion_map_screen.dart';

/// 탐색 탭 라우트 (감정칩+키워드 검색 + 지도 토글). 중앙 라우터에서 StatefulShellBranch로 끼움.
final List<RouteBase> emotionMapRoutes = [
  GoRoute(
    path: '/discover',
    name: 'discover',
    pageBuilder: (context, state) =>
        const MaterialPage(child: DiscoverScreen()),
  ),
  // 감정 지도 단독 화면(직접 접근용)
  GoRoute(
    path: '/emotion_map',
    name: 'emotionMap',
    pageBuilder: (context, state) =>
        const MaterialPage(child: EmotionMapScreen()),
  ),
];

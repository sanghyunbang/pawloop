// lib/core/widgets/layout/main_nav_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/core/widgets/nav/bottom_nav_bar.dart';

class MainNavShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainNavShell({super.key, required this.navigationShell});

  /// 바텀 네비 슬롯 → StatefulShellBranch 인덱스 매핑.
  ///
  /// 브랜치 순서(app_router): 0=explore, 1=record(schedule), 2=foryouV2,
  /// 3=journey, 4=profile, 5=emotionMap. 새 IA는 오늘(2)·감정지도(5)·[+기록]·피드(3)·나(4).
  /// Schedule(1)·explore(0)는 네비에서 강등(라우트는 유지, push로 접근).
  static const List<int> _slotToBranch = <int>[2, 5, 3, 4];

  void _onSlotTapped(int slot) {
    final branch = _slotToBranch[slot];
    final reselect = branch == navigationShell.currentIndex;
    navigationShell.goBranch(branch, initialLocation: reselect);
  }

  @override
  Widget build(BuildContext context) {
    final branchIndex = navigationShell.currentIndex;
    // 현재 브랜치가 네비 슬롯에 없으면(-1) 아무 탭도 강조하지 않음.
    final currentSlot = _slotToBranch.indexOf(branchIndex);

    return Scaffold(
      body: navigationShell, // 탭별 Navigator를 포함한 IndexedStack 렌더링
      floatingActionButton: HeatRecordFab(
        onPressed: () => context.push('/journey/diary/new'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: HeatBottomNavBar(
        currentSlot: currentSlot,
        onTap: _onSlotTapped,
      ),
    );
  }
}

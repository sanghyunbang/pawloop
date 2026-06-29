import 'package:flutter/material.dart';

const Color _kAccent = Color(0xFFFB6A3E);
const Color _kIdle = Color(0xFF9A9A9A);

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, this.activeIcon);
}

/// 새 IA(F0-4): 오늘 · 감정지도 · [+기록 FAB] · 피드 · 나
/// 슬롯 0,1 은 FAB 좌측, 2,3 은 우측에 배치됩니다.
const List<_NavItem> kNavItems = <_NavItem>[
  _NavItem('오늘', Icons.wb_sunny_outlined, Icons.wb_sunny),
  _NavItem('탐색', Icons.search_outlined, Icons.search),
  _NavItem('피드', Icons.dynamic_feed_outlined, Icons.dynamic_feed),
  _NavItem('나', Icons.person_outline, Icons.person),
];

/// 중앙 FAB를 위한 노치가 있는 바텀 네비게이션 바.
class HeatBottomNavBar extends StatelessWidget {
  /// 현재 선택된 슬롯(0~3). 네비에 없는 브랜치에 있을 땐 -1.
  final int currentSlot;
  final ValueChanged<int> onTap;

  const HeatBottomNavBar({
    super.key,
    required this.currentSlot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 10,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      height: 64,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _slot(0),
          _slot(1),
          const SizedBox(width: 64), // 중앙 FAB 공간
          _slot(2),
          _slot(3),
        ],
      ),
    );
  }

  Widget _slot(int i) {
    final item = kNavItems[i];
    final selected = currentSlot == i;
    return Expanded(
      child: InkResponse(
        onTap: () => onTap(i),
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              color: selected ? _kAccent : _kIdle,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? _kAccent : _kIdle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 중앙 "+기록" FAB.
class HeatRecordFab extends StatelessWidget {
  final VoidCallback onPressed;
  const HeatRecordFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: _kAccent,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      tooltip: '기록하기',
      child: const Icon(Icons.edit_note, size: 30),
    );
  }
}

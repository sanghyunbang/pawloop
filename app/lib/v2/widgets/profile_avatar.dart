import 'package:flutter/material.dart';
import '../screens/me_screen.dart';

/// 우상단 프로필 진입 아바타. 모든 메인 탭 공통.
class ProfileAvatar extends StatelessWidget {
  final double size;
  const ProfileAvatar({super.key, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MeScreen())),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD9C2), Color(0xFFE9C9FF)]),
          boxShadow: [BoxShadow(color: Color(0x40D89BFF), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Text('t', style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

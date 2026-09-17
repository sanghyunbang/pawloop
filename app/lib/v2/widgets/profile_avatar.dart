import '../data/auth_state.dart';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';
import '../screens/me_screen.dart';

/// 우상단 프로필 진입 아바타. 모든 메인 탭 공통. 테두리 색은 전역 [AppThemeCtl.avatarBorder].
class ProfileAvatar extends StatelessWidget {
  final double size;
  final bool tappable;
  const ProfileAvatar({super.key, this.size = 38, this.tappable = true});

  /// 로그인 전은 사람 아이콘, 뒤는 닉네임 첫 글자. 예전엔 모두에게 글자 't' 하나였다(#324).
  Widget _mark() {
    final name = AuthState.user?.nickname?.trim() ?? '';
    if (!AuthState.isAuthenticated || name.isEmpty) {
      return Icon(Icons.person_outline_rounded, size: size * 0.55, color: Colors.white);
    }
    return Text(
      name[0].toUpperCase(),
      style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final av = ValueListenableBuilder<Color>(
      valueListenable: AppThemeCtl.avatarBorder,
      builder: (_, border, __) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [T.glowStart, Color(0xFFE9C9FF)],
          ),
          border: Border.all(color: border, width: size >= 60 ? 3.5 : 2.5),
          boxShadow: [
            BoxShadow(
              color: border.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // 상태뿐 아니라 **내가 바뀐 것**도 듣는다 — 표시 이름을 고쳐도 상태는 그대로
        // authenticated 라, status 만 들으면 홈의 이 글자가 옛 이름의 첫 글자에 멈춘다(#665).
        child: ListenableBuilder(
          listenable: Listenable.merge([AuthState.status, AuthState.userRev]),
          builder: (_, __) => _mark(),
        ),
      ),
    );
    if (!tappable) return av;
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MeScreen())),
      child: av,
    );
  }
}

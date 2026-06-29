import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';
import '../widgets/aurora.dart';
import 'edit_screen.dart';

/// 프로필 (me) — 아바타 + 배경 테마 선택(앱 전체) + 메뉴.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  static const _avatarGrad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD9C2), Color(0xFFE9C9FF)]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0x80FFFFFF))),
                    child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('프로필', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                children: [
                  // 아바타 + 이름
                  Column(children: [
                    Container(
                      width: 88, height: 88, alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _avatarGrad,
                          boxShadow: [BoxShadow(color: Color(0x66D89BFF), blurRadius: 28, offset: Offset(0, 12))]),
                      child: const Text('t', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(height: 13),
                    const Text('tester', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: T.textPrimary)),
                    const SizedBox(height: 3),
                    const Text('localtest@example.com', style: TextStyle(fontSize: 13, color: Color(0x99463C64))),
                  ]),
                  const SizedBox(height: 18),
                  _themeCard(),
                  const SizedBox(height: 18),
                  _menuCard(context),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _themeCard() {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Text('배경 테마', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textPrimary)),
          Spacer(),
          Text('나에게 맞는 분위기로', style: TextStyle(fontSize: 12, color: Color(0x99463C64))),
        ]),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: AppThemeCtl.index,
          builder: (_, sel, __) => Row(
            children: [
              for (int i = 0; i < kThemes.length; i++) ...[
                if (i > 0) const SizedBox(width: 9),
                Expanded(child: _swatch(i, sel == i)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _swatch(int i, bool on) {
    final th = kThemes[i];
    return GestureDetector(
      onTap: () => AppThemeCtl.index.value = i,
      child: Column(children: [
        Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: th.swatch,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? const Color(0xFF2C2740) : const Color(0x332C2740), width: on ? 2.5 : 1),
            boxShadow: on
                ? const [BoxShadow(color: Color(0x385A4682), blurRadius: 18, offset: Offset(0, 8))]
                : const [BoxShadow(color: Color(0x145A4682), blurRadius: 10, offset: Offset(0, 4))],
          ),
        ),
        const SizedBox(height: 7),
        Text(th.name, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? T.textPrimary : T.textMuted)),
      ]),
    );
  }

  Widget _menuCard(BuildContext context) {
    Widget row(IconData icon, String label, {Color? color, bool border = true, VoidCallback? onTap}) {
      final c = color ?? T.textPrimary;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          decoration: BoxDecoration(border: border ? const Border(bottom: BorderSide(color: Color(0x1A8C7BFF))) : null),
          child: Row(children: [
            Icon(icon, size: 21, color: color ?? T.textSecondary),
            const SizedBox(width: 13),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c))),
            Icon(Icons.chevron_right, size: 20, color: color ?? const Color(0xFFBBB3CC)),
          ]),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(T.radius),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          row(Icons.edit, '프로필 편집', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditScreen()))),
          row(Icons.bookmark_border, '북마크', onTap: () {}),
          row(Icons.logout, '로그아웃', color: const Color(0xFFFF6B7E), border: false, onTap: () {}),
        ]),
      ),
    );
  }
}

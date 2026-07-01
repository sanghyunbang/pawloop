import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/auth_state.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';

/// Pawloop 로그인 — 카카오/네이버 소셜 로그인.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _login(String provider) async {
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await SocialLoginService.signIn(provider);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AuthState.markLoggedIn();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인됐어요 🐾')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                // 로고 히어로
                Container(
                  width: 120, height: 120, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)]),
                    boxShadow: [BoxShadow(color: Color(0x55FF9E7D), blurRadius: 30, offset: Offset(0, 14))],
                  ),
                  child: Image.asset('assets/emoji/dog.png', width: 76, height: 76),
                ),
                const SizedBox(height: 20),
                const Text('Pawloop',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: T.textPrimary)),
                const SizedBox(height: 8),
                const Text('반려동물과 함께 걷고,\n동네 반려인들과 연결되는 공간',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xB3463C64))),
                const Spacer(flex: 4),
                // 카카오
                _socialBtn(
                  label: '카카오로 시작하기',
                  bg: const Color(0xFFFEE500),
                  fg: const Color(0xFF191600),
                  icon: 'assets/icons/kakao.svg',
                  onTap: () => _login('kakao'),
                ),
                const SizedBox(height: 12),
                // 네이버
                _socialBtn(
                  label: '네이버로 시작하기',
                  bg: const Color(0xFF03C75A),
                  fg: Colors.white,
                  icon: 'assets/icons/naver.svg',
                  onTap: () => _login('naver'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('그냥 둘러보기', style: TextStyle(fontSize: 14, color: T.textMuted)),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialBtn({required String label, required Color bg, required Color fg, required String icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: _busy ? 0.6 : 1,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SvgPicture.asset(icon, width: 20, height: 20),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/auth_redirect.dart' show homeRoute;
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/auth_state.dart';
import 'package:heat_trip_flutter/features/auth/service/oauth_callback.dart';
import 'package:heat_trip_flutter/features/auth/service/social_login_service.dart';

/// 실패 사유별 안내 문구.
///
/// 예전에는 세 경우가 전부 "로그인에 실패했어요. 다시 시도해 주세요." 한 줄이었다.
/// 스스로 창을 닫은 사람에게 "실패" 라고 말하면 앱이 고장 난 줄 알고, 비행기 모드인
/// 사람에게 "다시 시도" 라고 말하면 될 때까지 누른다. (이슈 #12 완료 조건 9)
///
/// 순수 함수라 위젯 없이도 시험할 수 있다.
String loginFailureMessage(SocialLoginOutcome outcome) {
  switch (outcome) {
    case SocialLoginOutcome.canceled:
      return '로그인을 취소했어요.';
    case SocialLoginOutcome.networkError:
      return '네트워크에 연결할 수 없어요. 연결 상태를 확인해 주세요.';
    case SocialLoginOutcome.serverError:
      return '로그인 서버에 문제가 있어요. 잠시 후 다시 시도해 주세요.';
    case SocialLoginOutcome.success:
      // 호출되지 않는 분기지만, enum 이 늘어날 때 컴파일러가 알려주도록 남긴다.
      return '';
  }
}

/// "Sign in with Google" 버튼 라이트 테마 규격 색상.
/// 배경 흰색 · 테두리 #747775 · 텍스트 #1F1F1F — 브랜드 가이드가 고정한 값이다.
const Color _googleBg = Color(0xFFFFFFFF);
const Color _googleBorder = Color(0xFF747775);
const Color _googleFg = Color(0xFF1F1F1F);

/// "Sign in with Apple" 버튼 규격(HIG) — 검정 배경 · 흰 로고와 글자. 문구는 승인된 셋
/// ("Apple로 로그인" · "Apple로 가입하기" · "Apple로 계속하기") 중 하나여야 한다.
const Color _appleBg = Color(0xFF000000);
const Color _appleFg = Color(0xFFFFFFFF);

/// Pawloop 로그인 — 카카오 · 구글 · Apple(#301). **세 개 다 플랫폼과 상관없이 보인다**(#544).
///
/// 네이버는 화면에서만 내렸다. `NaverOAuth2User`와 백엔드 설정은 그대로 살아 있으므로
/// `_login('naver')`를 부르는 버튼만 다시 넣으면 언제든 되살릴 수 있다. (이슈 #3)
class LoginScreen extends StatefulWidget {
  /// Apple 버튼을 그릴지. `null` 이면 **어느 플랫폼에서든** 그린다(#544).
  ///
  /// 처음에는 iOS 에서만 그렸다 — 심사 지침 4.8 이 iOS 앱에 적용되고, 안드로이드 사용자에게
  /// Apple 계정을 권할 이유가 없다고 봤다(#301). **그런데 그 규칙은 계정을 가둔다.** 아이폰에서
  /// "Apple로 가입" 한 사람이 안드로이드 앱을 깔면 카카오 · 구글 계정이 따로 없어서 **들어올
  /// 방법이 아예 없다.** 애플이 안드로이드 · 윈도우 · 웹에서 쓰라고 버튼을 열어 둔 이유가 이것이고,
  /// 널리 쓰이는 안내(WillowTree 라이브러리 · Firebase · Google Identity Platform)도 "두 앱이
  /// 있고 제3자 로그인을 쓰면 안드로이드에도 넣으라" 로 같다.
  ///
  /// 대칭도 맞는다 — iOS 에서 구글 · 카카오를 보여주면서 안드로이드에서만 Apple 을 빼는 것은
  /// 한쪽으로만 기운 규칙이다. 맥북 · 아이패드를 쓰는 안드로이드폰 사용자도 애플 계정이 있다.
  ///
  /// 우리 Apple 로그인은 **카카오 · 구글과 같은 웹 왕복**이라(`SocialLoginService.signIn`)
  /// 안드로이드 전용 SDK 가 필요 없다. 테스트가 명시적으로 켜고 끈다.
  final bool? showAppleSignIn;

  /// 왜 이 화면에 왔는지 한 줄. 게스트가 막힌 자리에서 보낼 때 그 자리가 넘긴다(#517).
  ///
  /// 예전에는 부르는 쪽이 **스낵바**로 말하고 곧바로 이 화면을 밀어 올렸다. 스낵바는
  /// 1.6초 뒤 사라지고 전환 애니메이션이 그중 0.3초를 먹는다 — 걸으러 온 사람은 로그인
  /// 화면을 보면서 "내가 뭘 눌렀더라" 를 다시 떠올려야 했다. 이유는 화면이 들고 있어야
  /// 사용자가 읽을 때까지 남는다.
  final String? reason;

  const LoginScreen({super.key, this.showAppleSignIn, this.reason});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _login(String provider) async {
    setState(() => _busy = true);
    AuthState.beginAuthenticating();

    SocialLoginResult result;
    try {
      result = await SocialLoginService.signIn(provider);
    } catch (e) {
      // signIn 은 예외를 삼키지만, 그래도 여기서 앱이 죽지 않게 한 겹 더 둔다.
      result = SocialLoginResult(outcomeFromError(e));
    }

    // 스낵바를 띄울 messenger 는 await 전에 잡아 둔다 — 성공 시 이 화면은
    // 곧 pop 되고, 그 뒤의 `ScaffoldMessenger.of(context)` 는 죽은 context 를 본다.
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (!result.ok) {
      AuthState.cancelAuthenticating();
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(loginFailureMessage(result.outcome))),
      );
      return;
    }

    // 로그인 화면을 먼저 걷어낸다. 그래야 온보딩 리다이렉트가 이 화면 뒤에서
    // 일어나 사용자에게 보이지 않는 일이 없다.
    if (navigator.canPop()) navigator.pop();

    // 서버에 "나는 누구인가" 를 물어 상태를 확정한다. isNew 면 라우터가 온보딩으로 보낸다.
    await AuthState.completeLogin(isNew: result.isNew);

    if (mounted) setState(() => _busy = false);
    messenger.showSnackBar(
      const SnackBar(content: Text('로그인됐어요')),
    );
  }

  /// "그냥 둘러보기" — 로그인 없이 앱을 계속 쓴다.
  ///
  /// 이 화면은 두 경로로 뜬다: 프로필 메뉴에서 `push` 로 얹히거나, 라우터가
  /// `/auth/login` 으로 보내거나(세션 만료·보호 라우트 진입). pop 할 게 없는
  /// 두 번째 경우까지 생각하지 않으면 버튼이 아무것도 안 하는 화면이 된다.
  void _dismiss() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final showApple = widget.showAppleSignIn ?? true;
    return Scaffold(
      backgroundColor: T.bgTop,
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
                    gradient: RadialGradient(colors: [T.glowStart, T.glowEnd]),
                    boxShadow: [BoxShadow(color: T.sigGlow, blurRadius: 30, offset: Offset(0, 14))],
                  ),
                  child: Image.asset('assets/emoji/dog_face.png', width: 76, height: 76),
                ),
                const SizedBox(height: 20),
                const Text('Pawloop',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: T.textPrimary)),
                const SizedBox(height: 8),
                const Text('반려동물과 함께 걷고,\n동네 반려인들과 연결되는 공간',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: T.textSecondary)),
                if (widget.reason != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('login-reason'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0x14E04A2B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(widget.reason!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: T.warmText)),
                  ),
                ],
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
                // 구글 — 브랜드 가이드(developers.google.com/identity/branding-guidelines)상
                // 흰 배경 + 회색 테두리 + 검정 텍스트 + 공식 4색 "G" 로고가 고정이다.
                // 임의로 색을 바꾸지 말 것. (login_screen_test 가 회귀로 잠가 둔다)
                _socialBtn(
                  label: 'Google로 시작하기',
                  bg: _googleBg,
                  fg: _googleFg,
                  border: _googleBorder,
                  icon: 'assets/icons/google.svg',
                  onTap: () => _login('google'),
                ),
                if (showApple) ...[
                  const SizedBox(height: 12),
                  // Apple — 서버가 OIDC 로 계정을 만든다. 앱의 흐름은 카카오·구글과 같다(#301).
                  _socialBtn(
                    label: 'Apple로 계속하기',
                    bg: _appleBg,
                    fg: _appleFg,
                    iconWidget: const Icon(Icons.apple, size: 22, color: _appleFg),
                    onTap: () => _login('apple'),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _dismiss,
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

  Widget _socialBtn({
    required String label,
    required Color bg,
    required Color fg,
    String? icon,
    Widget? iconWidget,
    required VoidCallback onTap,
    Color? border,
  }) {
    assert(icon != null || iconWidget != null, '아이콘 하나는 있어야 한다');
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: _busy ? 0.6 : 1,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            iconWidget ?? SvgPicture.asset(icon!, width: 20, height: 20),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}

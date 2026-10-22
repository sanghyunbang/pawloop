import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/auth_redirect.dart' show homeRoute;
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../data/auth_state.dart';
import '../data/login_terms_gate.dart';
import 'settings/legal_document_screen.dart';
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

/// 체크하기 전에 소셜 버튼을 눌렀을 때 — 무엇이 모자란지 말한다.
const String loginTermsRequiredMessage = '이용약관과 개인정보처리방침에 동의하면 시작할 수 있어요';

/// 체크칸 아래 한 줄 — 약관 제6조의 무관용을 동의하는 자리에서 먼저 말한다(애플 지침 1.2).
const String loginZeroToleranceNote = '불쾌한 콘텐츠와 괴롭힘은 일절 허용되지 않아요';

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
///
/// ## 약관 동의가 버튼 위에 있다 — 애플 지침 1.2
///
/// 1.2 는 "가입·로그인 **전에** 이용약관에 동의를 받으라" 고 요구한다. 그래서 소셜 버튼 위에 체크칸
/// 하나("이용약관과 개인정보처리방침에 동의합니다")를 두고, **체크해야 세 버튼이 켜진다.** 두 문서는
/// 동의 화면이 쓰는 [LegalDocumentScreen] 으로 연다. "그냥 둘러보기" 는 가입이 아니라 체크 없이 켜져
/// 있다. 왜 여기인지·무엇을 기억하는지는 [LoginTermsGate] 머리말에 있다. 로그인 뒤 동의 화면
/// (`consent_screen.dart`)은 그대로 뜬다.
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

  /// 로그인 전 약관 동의를 기억하는 자리. **테스트만 넘긴다.**
  final LoginTermsGate? termsGate;

  const LoginScreen({super.key, this.showAppleSignIn, this.reason, this.termsGate});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  late final LoginTermsGate _terms = widget.termsGate ?? const LoginTermsGate();

  /// 이용약관 · 개인정보처리방침에 동의했는가. **체크해야 소셜 버튼 셋이 켜진다**(1.2).
  bool _agreed = false;

  /// 사용자가 체크칸을 한 번이라도 건드렸는가. 기기에 남은 동의를 늦게 읽어 왔을 때, 그사이 사용자가
  /// 직접 고른 것을 덮어쓰지 않으려고 둔다.
  bool _touched = false;

  late final TapGestureRecognizer _termsLink = TapGestureRecognizer()
    ..onTap = () => _openDocument(LegalDocument.terms);
  late final TapGestureRecognizer _privacyLink = TapGestureRecognizer()
    ..onTap = () => _openDocument(LegalDocument.privacy);

  @override
  void initState() {
    super.initState();
    _restoreAgreement();
  }

  @override
  void dispose() {
    _termsLink.dispose();
    _privacyLink.dispose();
    super.dispose();
  }

  /// 이 기기가 **지금 버전의** 두 문서에 동의한 적이 있으면 체크된 채로 보여 준다([LoginTermsGate]).
  Future<void> _restoreAgreement() async {
    final agreed = await _terms.hasAgreed();
    if (!mounted || !agreed || _touched) return;
    setState(() => _agreed = true);
  }

  void _toggleAgreement() {
    final next = !_agreed;
    setState(() {
      _agreed = next;
      _touched = true;
    });
    // 풀었으면 기억도 지운다 — 풀어 둔 체크가 다음에 켜져 있으면 사용자의 마지막 뜻과 다르다.
    if (!next) unawaited(_terms.clear());
  }

  /// 약관 전문 — 동의 화면이 여는 것과 **같은 화면**이다. 원문은 asset 하나뿐이다(#165).
  void _openDocument(LegalDocument document) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LegalDocumentScreen(document: document),
    ));
  }

  /// 체크하지 않고 소셜 버튼을 눌렀다 — 로그인을 시작하지 않고, 무엇이 모자란지 말한다.
  void _askForAgreement() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(loginTermsRequiredMessage)));
  }

  Future<void> _login(String provider) async {
    if (!_agreed) {
      _askForAgreement();
      return;
    }
    // 체크한 채로 눌렀다 — 이 기기에 지금 버전과 함께 남긴다. 기다리지 않는다: 못 적어도 다음에 한 번
    // 더 체크할 뿐이고, 로그인 왕복을 그 뒤에 세울 이유가 없다.
    unawaited(_terms.markAgreed());
    setState(() => _busy = true);
    AuthState.beginAuthenticating();

    SocialLoginResult result;
    try {
      result = await SocialLoginService.signIn(provider);
    } catch (e) {
      // signIn 은 예외를 삼키지만, 그래도 여기서 앱이 죽지 않게 한 겹 더 둔다.
      result = SocialLoginResult(outcomeFromError(e));
    }

    // ## 왕복의 결과는 이 화면의 생존에 걸려 있지 않다 — 이슈 #673 ㄷ
    //
    // 예전에는 여기가 `if (!mounted) return;` 이었다. 그래서 왕복 중에 이 화면이
    // 사라지면(#673 은 그 길을 하나 보여 준다 — `/home` 페이지가 갈아 끼워지면 그 위에
    // `push` 로 얹힌 이 화면도 함께 제거된다) **성공한 로그인이 `completeLogin` 에
    // 닿지 못했다.** 실패도 마찬가지로 `cancelAuthenticating` 에 닿지 못해 상태가
    // `authenticating` 에 멈췄고, 그 상태에서 `authRedirect` 는 어디로도 안 보내므로
    // 앱이 그 자리에 굳는다.
    //
    // 그래서 **상태를 확정하는 일은 무조건 하고**, 화면에 말하는 일(스낵바·pop)만
    // `mounted` 를 본다. 스낵바를 띄울 messenger 는 pop 전에 잡아 둔다 — 성공 시 이
    // 화면은 곧 pop 되고, 그 뒤의 `ScaffoldMessenger.of(context)` 는 죽은 context 를 본다.
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    if (!result.ok) {
      AuthState.cancelAuthenticating();
      if (!mounted) return;
      setState(() => _busy = false);
      messenger!.showSnackBar(
        SnackBar(content: Text(loginFailureMessage(result.outcome))),
      );
      return;
    }

    // 로그인 화면을 먼저 걷어낸다. 그래야 온보딩 리다이렉트가 이 화면 뒤에서
    // 일어나 사용자에게 보이지 않는 일이 없다.
    if (mounted) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    }

    // 서버에 "나는 누구인가" 를 물어 상태를 확정한다. isNew 면 라우터가 온보딩으로 보낸다.
    await AuthState.completeLogin(isNew: result.isNew);

    if (mounted) setState(() => _busy = false);
    messenger?.showSnackBar(
      const SnackBar(content: Text('로그인됐어요')),
    );
  }

  /// "그냥 둘러보기" — **언제나 홈으로** 간다.
  ///
  /// 예전에는 `canPop()` 이면 `pop()` 했다. 프로필에서 이 화면을 열었으면 프로필로
  /// 돌아간다는 뜻인데, **게스트 프로필은 "로그인하세요" 말고 할 것이 없는 화면**이다.
  /// 둘러보라고 적어 놓고 로그인하라는 화면으로 되돌리니 고리가 됐다(신고).
  ///
  /// 라벨이 약속한 것을 한다. 취소가 필요하면 뒤로가기가 이미 있다 — 이 버튼은
  /// "로그인 안 하고 앱을 쓰겠다" 는 뜻이고, 그 자리는 홈이다.
  ///
  /// 뒤에 쌓인 화면은 함께 정리한다. 안 그러면 홈에서 뒤로가기를 눌렀을 때 방금
  /// 떠난 로그인 화면이 다시 나온다.
  void _dismiss() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      // 라우터가 있으면 그것이 정본이다 — 얹힌 화면을 걷어내고 홈 페이지로.
      Navigator.of(context).popUntil((route) => route.isFirst);
      router.go(homeRoute);
      return;
    }
    // 라우터 밖에서 띄운 경우(위젯 테스트 등)는 닫는 것까지만 한다.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final showApple = widget.showAppleSignIn ?? true;
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          // 키가 작은 폰 · 큰 글자에서는 스크롤된다. 약관 체크칸이 들어오며 기본 창(800×600)에서도 30px
          // 넘쳤다(이유 알약이 있을 때). 자리가 넉넉하면 예전처럼 Spacer 가 화면을 나눠 채운다 — 최소 높이를
          // 화면에 맞추고 IntrinsicHeight 로 Spacer 가 남는 자리를 갖게 한다.
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, _bottomPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, viewport.maxHeight - _bottomPadding)),
                child: IntrinsicHeight(
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
                      // 약관 동의 — 체크해야 아래 세 버튼이 켜진다(애플 지침 1.2).
                      _termsAgreement(),
                      const SizedBox(height: 14),
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
          ),
        ),
      ),
    );
  }

  /// 아래 여백. 스크롤 안쪽 여백이라, 최소 높이를 화면에 맞출 때 이만큼 뺀다.
  static const double _bottomPadding = 32;

  /// 소셜 버튼 위의 필수 체크칸 — "이용약관과 개인정보처리방침에 동의합니다".
  ///
  /// 두 문서 이름이 링크다. 체크칸·문장의 나머지를 누르면 켜고 끈다. 아래 한 줄은 약관 제6조의 무관용
  /// 조항을 동의하는 자리에서 먼저 말한다 — 링크를 안 여는 사람도 읽는다.
  Widget _termsAgreement() {
    const link = TextStyle(
      fontWeight: FontWeight.w800,
      color: T.textPrimary,
      decoration: TextDecoration.underline,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        checked: _agreed,
        child: GestureDetector(
          key: const Key('login-terms-agree'),
          onTap: _busy ? null : _toggleAgreement,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              // 문장 가운데를 누르면 링크가 열릴 수 있다 — 체크만 하려면 동그라미를 누른다(검사도 여기를 누른다).
              KeyedSubtree(key: const Key('login-terms-check'), child: _check(_agreed)),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '이용약관', style: link, recognizer: _termsLink),
                    const TextSpan(text: '과 '),
                    TextSpan(text: '개인정보처리방침', style: link, recognizer: _privacyLink),
                    const TextSpan(text: '에 동의합니다'),
                  ]),
                  key: const Key('login-terms-text'),
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textSecondary),
                ),
              ),
            ]),
          ),
        ),
      ),
      const Padding(
        // 체크(22) + 사이(10) 만큼 밀어 문장 첫 글자와 같은 선에 선다.
        padding: EdgeInsets.only(left: 32),
        child: Text(loginZeroToleranceNote,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: T.textMuted)),
      ),
    ]);
  }

  /// 동의 화면(`consent_screen.dart`)의 체크와 같은 모양 — 미체크는 빈 원이다(#325).
  Widget _check(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? T.warmMid : Colors.transparent,
          border: on ? null : Border.all(color: const Color(0x66463C64), width: 1.6),
        ),
        child: on ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
      );

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
    // 체크하기 전에는 흐리게 그린다 — 눌러도 로그인이 시작되지 않고 무엇이 모자란지만 말한다.
    final enabled = !_busy && _agreed;
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
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

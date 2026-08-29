// lib/features/auth/presentation/login_screen.dart
//
// ## 이 화면의 역할 — **이메일/비밀번호 로그인(보조 경로)** 이다 (이슈 #12)
//
// 앱에는 `LoginScreen` 이라는 이름의 화면이 두 개 있었고, 어느 쪽이 진짜인지
// 코드만 보고는 알 수 없었다. #12 에서 정본을 정했다.
//
//  - **정본**: `lib/v2/screens/login_screen.dart` — 카카오/구글 소셜 로그인.
//    라우터 name `'login'`(`/auth/login`)이 가리키는 곳이고, 세션 만료(#11)와
//    보호 라우트 진입이 사용자를 보내는 곳도 여기다.
//  - **이 파일**: `POST /auth/login` + `POST /auth/signup` 계약(#10)을 쓰는
//    이메일 경로. 회원가입 화면(`sign_up_screen.dart`)과 짝이라 지우지 않고
//    `/auth/login/email`(name `'loginEmail'`)로 남겨 둔다.
//
// 여기 있던 **주석 처리된 소셜 로그인 버튼들은 삭제했다** — 정본이 따로 있는데
// 주석으로 남겨 두면 다음 사람이 "이걸 살리면 되나" 를 매번 다시 판단해야 한다.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart'; // ✅ 유지
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/login_request.dart';
import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthRepositoryImpl _authRepository = AuthRepositoryImpl();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  // ✅ 추가: 비밀번호 보이기/가리기 토글 상태
  bool _obscureLoginPw = true;

  // === 원본 기능 그대로 ===
  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showDialog('이메일과 비밀번호를 모두 입력해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final tokens = await _authRepository.login(
        LoginRequest(email: email, password: password),
      );
      if (tokens != null) {
        // 평문 SharedPreferences 가 아니라 보안 저장소에 저장한다 (#8).
        //
        // **refresh 토큰도 함께 저장한다** (#9·#11). 예전에는 AT 만 저장했고,
        // 그래서 AT 가 만료되는 순간(1시간) 사용자는 조용히 로그아웃됐다.
        await SecureTokenStore.instance.writeTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        );

        // 토큰만 저장하고 화면을 옮기면 앱은 여전히 "내가 누군지" 모른다.
        // `GET /auth/me` 로 상태를 확정한다. isNew 면 라우터가 온보딩으로 보낸다(#12).
        await AuthState.completeLogin(isNew: tokens.isNew);
        if (!mounted) return;

        // 신규 가입자는 라우터의 redirect 가 온보딩으로 붙잡으므로 여기서 미리
        // 가로채지 않는다. 기존 사용자만 "오늘" 홈으로 보낸다 (새 IA, F0-4).
        if (!tokens.isNew) context.go('/foryou_v2');
      } else {
        _showDialog('[로그인 실패] 아이디와 비밀번호를 확인해주세요.');
      }
    } catch (e) {
      _showDialog('오류 발생: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === 원본 기능 그대로 ===
  void _showDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('알림'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // sign_up_screen 과 동일 톤
    const startBg = Color(0xFFF8F2E7);
    const fieldFill = Color(0xFFF2F4F7);
    const accent = Color(0xFFEB9C64);

    // 상단 고정 헤더 높이
    const double headerHeight = 120;

    return Scaffold(
      backgroundColor: startBg,

      // 투명 AppBar (뒤로가기만 담당 / 기능 변경 없음)
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '뒤로',
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          // 뒤로갈 곳이 있으면 pop, 아니면 start로 이동
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed('start');
            }
          },
        ),
      ),

      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 헤더: 상단 고정 ──
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: headerHeight,
              child: Container(
                color: startBg,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      // 필요 시 로고 사용 (assets 경로 맞으면 주석 해제)
                      // Image(image: AssetImage('assets/Logo4.png'), height: 64),
                      // SizedBox(height: 10),
                      Text(
                        'Log In',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Please log in to continue',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 입력 카드(모달 느낌) + 소셜 로그인: 헤더 아래에서 시작 ──
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, headerHeight + 20, 16, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ======= 원본 기능/필드 그대로 =======
                      _label('이메일'),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _filledDecoration(
                          hint: 'example@gmail.com',
                          fill: fieldFill,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _label('비밀번호'),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscureLoginPw, // ✅ 토글 적용
                        decoration:
                            _filledDecoration(
                              hint: '••••••••',
                              fill: fieldFill,
                            ).copyWith(
                              // ✅ 눈 아이콘 토글
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureLoginPw
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.black38,
                                ),
                                onPressed: () => setState(
                                  () => _obscureLoginPw = !_obscureLoginPw,
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(height: 20),

                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _handleEmailLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('이메일 로그인'),
                              ),
                            ),

                      const SizedBox(height: 24),
                      const Divider(),

                      // ⬇️ 여기부터 회원가입 링크 (카드 내부)
                      const SizedBox(height: 16),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '아직 계정이 없으신가요? ',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.goNamed(
                                'signUp',
                              ), // or: context.go('/auth/sign-up')
                              child: const Text(
                                '회원가입',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  // 디자인 톤에 맞추고 싶으면 accent 색을 써도 됩니다.
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 디자인용 헬퍼 (기능 변경 없음) =====
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: .4,
        color: Color(0xFF70757D),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  InputDecoration _filledDecoration({
    required String hint,
    Color fill = const Color(0xFFF2F4F7),
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: _border(),
      enabledBorder: _border(),
      focusedBorder: _border(color: Colors.black87),
    );
  }

  OutlineInputBorder _border({Color color = Colors.transparent}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1),
      );
}

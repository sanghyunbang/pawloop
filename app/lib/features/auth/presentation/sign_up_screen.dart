// lib/features/auth/presentation/sign_up_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/app/auth_redirect.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/register_request.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // ===== Consts =====
  static const Color _startBg = Color(0xFFF8F2E7);
  static const Color _fieldFill = Color(0xFFF2F4F7);
  static const Color _accent = Color(0xFFEB9C64);
  // 약관 동의는 이 화면에 없다. 가입 뒤 첫 로그인에서 동의 화면(ConsentScreen)이 한 번
  // 받고 서버(user_consent)에 적는다(#190). 예전에는 여기서도 받고 로그인 뒤에 또 받았다 —
  // 같은 사람에게 두 번 묻는 화면이었다.

  // ===== Form / State =====
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _nameController = TextEditingController();

  String _gender = 'male'; // 'male' | 'female' | 'other'
  String _ageGroup = 'over14'; // 'over14' | 'under14'

  bool _isLoading = false;
  bool _obscurePw = true;

  final _authRepository = AuthRepositoryImpl();

  // ===== Lifecycle =====
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // ★ 서버가 요구하는 신규 필드까지 포함한 DTO 생성
    final req = RegisterRequest(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      nickname: _nicknameController.text.trim(),
      name: _nameController.text.trim(),
      gender: _gender, // 'male' | 'female' | 'other'
      ageGroup: _ageGroup, // 'over14' | 'under14'
    );

    // (선택) 디버그: 실제 전송 바디 확인
    // debugPrint(req.toJson().toString());

    final outcome = await _authRepository.register(req);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (outcome == RegisterOutcome.created) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('회원가입 완료')));
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      context.goNamed('login');
      return;
    }

    // 409 를 400 과 구분해 안내한다 — 이미 계정이 있는 사용자에게
    // "다시 시도해주세요" 는 아무 도움이 안 된다 (#10 이 상태 코드를 나눴다).
    final message = switch (outcome) {
      RegisterOutcome.duplicateEmail => '이미 가입된 이메일입니다. 로그인해주세요.',
      RegisterOutcome.invalidInput => '입력한 정보를 다시 확인해주세요.',
      _ => '회원가입 실패. 다시 시도해주세요.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _startBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: '뒤로',
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          // 정본 로그인 화면으로. `start` 는 레거시 시작 화면이다 (#184).
          onPressed: () => context.go(loginRoute),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 헤더
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 120,
              child: Container(
                color: _startBg,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Please sign up to get started',
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

            // 폼
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 140, 16, 16),
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
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label('이메일'),
                              _filledField(
                                controller: _emailController,
                                hint: 'example@gmail.com',
                                keyboardType: TextInputType.emailAddress,
                                fill: _fieldFill,
                                validator: (value) {
                                  if (value == null ||
                                      value.isEmpty ||
                                      !value.contains('@')) {
                                    return '유효한 이메일을 입력하세요';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              _label('비밀번호'),
                              _filledField(
                                controller: _passwordController,
                                hint: '••••••••',
                                obscureText: _obscurePw,
                                fill: _fieldFill,
                                validator: (value) =>
                                    value == null || value.length < 8
                                    ? '8자 이상 입력하세요'
                                    : null,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePw
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.black38,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePw = !_obscurePw),
                                ),
                              ),
                              const SizedBox(height: 14),

                              _label('닉네임'),
                              // 서버·계약과 같은 수다(#229). 없으면 21자를 쓴 사람이
                              // 가입 버튼을 누른 뒤에야 400 을 받는다.
                              _filledField(
                                controller: _nicknameController,
                                maxLength: AuthRepositoryImpl.maxNicknameLength,
                                hint: '닉네임을 입력하세요',
                                fill: _fieldFill,
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? '닉네임을 입력하세요'
                                    : null,
                              ),
                              const SizedBox(height: 14),

                              _label('이름'),
                              _filledField(
                                controller: _nameController,
                                maxLength: AuthRepositoryImpl.maxNameLength,
                                hint: '이름을 입력하세요',
                                fill: _fieldFill,
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? '이름을 입력하세요'
                                    : null,
                              ),
                              const SizedBox(height: 14),

                              _label('성별'),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _radioTile(
                                      title: '남자',
                                      value: 'male',
                                      group: _gender,
                                      onChanged: (v) =>
                                          setState(() => _gender = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _radioTile(
                                      title: '여자',
                                      value: 'female',
                                      group: _gender,
                                      onChanged: (v) =>
                                          setState(() => _gender = v!),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              _label('나이 구분'),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _radioTile(
                                      title: '만 14세 이상',
                                      value: 'over14',
                                      group: _ageGroup,
                                      onChanged: (v) =>
                                          setState(() => _ageGroup = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _radioTile(
                                      title: '만 14세 미만',
                                      value: 'under14',
                                      group: _ageGroup,
                                      onChanged: (v) =>
                                          setState(() => _ageGroup = v!),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              const Text(
                                '약관 동의는 가입 뒤 첫 로그인에서 받아요.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submitForm,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
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
                                  child: const Text('회원가입'),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Small UI helpers =====
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

  Widget _filledField({
    required TextEditingController controller,
    required String hint,
    Color fill = _fieldFill,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffixIcon,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      obscureText: obscureText,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(color: Colors.black87),
        suffixIcon: suffixIcon,
      ),
    );
  }

  OutlineInputBorder _border({Color color = Colors.transparent}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1),
      );

  Widget _radioTile({
    required String title,
    required String value,
    required String group,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: group,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

}

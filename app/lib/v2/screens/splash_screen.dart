import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 앱 시작 직후 — 저장된 토큰을 `GET /auth/me` 로 검증하는 동안 머무는 화면.
///
/// 이 화면이 없으면 앱은 검증이 끝나기 전에 홈이나 로그인 화면 중 하나를 찍고,
/// 검증 결과가 반대면 그 화면을 갈아치운다. 그게 사용자에게는 "로그인 화면이
/// 깜빡였다가 홈으로 넘어가는" 현상으로 보인다(이슈 #12 완료 조건 7).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [T.glowStart, T.glowEnd],
                  ),
                ),
                child: Image.asset('assets/emoji/dog_face.png', width: 60, height: 60),
              ),
              const SizedBox(height: 22),
              const Text(
                'Pawloop',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

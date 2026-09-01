import 'package:flutter/material.dart';
import '../widgets/pet_registration_sheet.dart';

import '../data/auth_state.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 신규 가입자(`isNew == true`)가 처음 도착하는 자리 — **임시 화면**이다.
///
/// 이슈 #12 의 범위는 "라우팅 분기와 자리" 까지다. 반려동물 프로필 등록 폼 자체는
/// 이 이슈 밖이라 일부러 만들지 않았다. 여기에 화면을 채워 넣는 것이 다음 작업이고,
/// 그때 [AuthState.completeOnboarding] 을 등록 완료 시점으로 옮기면 된다.
///
/// 지금은 "나중에 할래요" 로 건너뛸 수 있다 — 건너뛰기가 없으면 신규 가입자가
/// 앱에 갇힌다(라우터가 온보딩 밖으로 나가지 못하게 막고 있다).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = AuthState.user?.nickname;

    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 108,
                  height: 108,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFFFFE7D2), Color(0xFFFFD0C0)],
                    ),
                  ),
                  child: Image.asset(
                    'assets/emoji/dog.png',
                    width: 68,
                    height: 68,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  name == null ? '환영해요!' : '$name 님, 환영해요!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: T.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '반려동물 프로필을 등록하면\n산책 기록과 추천이 훨씬 정확해져요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xB3463C64),
                  ),
                ),
                const Spacer(flex: 4),
                // 등록을 **강제하지 않는다** — 로그인 화면에 "그냥 둘러보기" 가 있는데
                // 여기서 필수로 만들면 구경만 하려는 사람도 폼을 채워야 한다.
                // 건너뛴 사람은 산책을 저장하려는 순간 잡는다(create_screen) — 그때가
                // 사용자가 "왜 필요한지" 아는 유일한 시점이다 (#159).
                FilledButton(
                  onPressed: () async {
                    final registered = await showPetRegistrationSheet(
                      context,
                      reason: '등록하면 산책 기록이 서버에 남아요',
                    );
                    // 등록했든 닫았든 온보딩은 끝난다. 닫았다면 나중에 다시 권한다.
                    if (registered != null || context.mounted) {
                      AuthState.completeOnboarding();
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('우리 아이 등록하기'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: AuthState.completeOnboarding,
                  child: const Text(
                    '나중에 할래요',
                    style: TextStyle(fontSize: 14, color: T.textMuted),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

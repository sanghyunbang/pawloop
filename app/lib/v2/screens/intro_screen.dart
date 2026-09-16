// lib/v2/screens/intro_screen.dart
//
// 첫 실행 소개 — 가치 3장, 건너뛰기, 한 번만, 로그인 화면 앞에 (#323).
//
// ## 무엇을 말하고 무엇을 말하지 않나
//
// 세 장은 `docs/00-product/concept.md` §2 의 핵심 가치 세 줄이다. **사용법은 말하지
// 않는다** — 카드 넘기기식 튜토리얼은 과업 성과를 거의 못 올리고(NN/g, Mobile
// Tutorials), 필요한 안내는 그 기능을 처음 쓰는 순간에 그 자리에서 한다(위치 권한은
// 첫 산책, 채팅 규칙은 첫 채팅). 없는 기능(추천·알림)은 쓰지 않는다.
//
// "건너뛰기" 와 "시작하기" 는 **같은 곳(로그인 화면)** 으로 간다. 로그인 화면에
// "그냥 둘러보기" 가 있으므로 여기서 갈림길을 하나 더 만들 이유가 없다.
//
// `onboarding_screen.dart`(소셜 첫 로그인 뒤 반려동물 등록 권유)와 다른 화면이다.
// 그쪽은 계정이 생긴 뒤, 이쪽은 계정이 생기기 전이다.
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 한 장의 내용. 그림은 이모지 자산(`assets/emoji/*.png`) 아니면 아이콘 하나다 —
/// 디자인 시스템이 Fluent 3D 이모지를 쓰므로 시스템 이모지 글자는 넣지 않는다.
class IntroPage {
  const IntroPage({
    required this.title,
    required this.body,
    this.asset,
    this.icon,
    required this.tint,
  }) : assert(asset != null || icon != null);

  final String title;
  final String body;
  final String? asset;
  final IconData? icon;
  final Color tint;
}

/// 세 장. 순서는 `concept.md` §5 의 하루 루프(기록 → 발견 → 연결)와 같다.
const List<IntroPage> kIntroPages = [
  IntroPage(
    title: '산책이 그냥\n사라지지 않아요',
    body: '걸은 거리·시간·경로가 자동으로 기록되고\n주간 통계로 쌓여요.',
    asset: 'assets/emoji/paw.png',
    tint: T.auroraPeach,
  ),
  IntroPage(
    title: '어디로 갈지\n고민이 줄어요',
    body: '반려동반 장소·동물병원·산책로를\n한 지도에서 찾아요.',
    icon: Icons.map_rounded,
    tint: T.auroraMint,
  ),
  IntroPage(
    title: '혼자 걷지 않아요',
    body: '가족과 오늘의 케어를 나누고,\n동네 반려인들과 이야기해요.',
    asset: 'assets/emoji/dog_face.png',
    tint: T.auroraLilac,
  ),
];

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone, this.replay = false});

  /// 건너뛰기든 시작하기든 화면을 떠날 때 한 번 부른다. 첫 실행이면 라우터가
  /// "봤음" 을 적고 로그인 화면으로 보내고, 설정에서 다시 볼 때는 그냥 닫는다.
  final VoidCallback onDone;

  /// 설정 > 앱 소개 다시 보기 로 열었는가. 문구가 "닫기" 로 바뀐다.
  final bool replay;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _index == kIntroPages.length - 1;

  /// 두 번 불리지 않게 잠근다 — 버튼을 연타하면 `go` 가 두 번 돈다.
  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _next() {
    if (_last) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      widget.replay ? '닫기' : '건너뛰기',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: T.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: kIntroPages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _IntroCard(page: kIntroPages[i]),
                ),
              ),
              _Dots(count: kIntroPages.length, index: _index),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                child: _PrimaryButton(
                  label: _last ? (widget.replay ? '닫기' : '시작하기') : '다음',
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.page});

  final IntroPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  T.surface,
                  page.tint.withValues(alpha: 0.75),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: page.tint.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: page.asset != null
                ? Image.asset(page.asset!, width: 76, height: 76)
                : Icon(page.icon, size: 68, color: T.textPrimary),
          ),
          const SizedBox(height: 34),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
            child: Column(
              children: [
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.28,
                    fontWeight: FontWeight.w800,
                    color: T.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: T.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            key: ValueKey('intro-dot-$i'),
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i == index ? T.sigStart : T.textFaint,
            ),
          ),
      ],
    );
  }
}

/// 로그인·동의 화면의 주 버튼과 같은 그라데이션.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [T.sigStart, T.sigEnd]),
          boxShadow: [
            BoxShadow(
              color: T.sigStart.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

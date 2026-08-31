import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 각 메뉴 클릭 시 이동할 화면들
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/feedback_screen.dart';
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/share_app_screen.dart';
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/terms_screen.dart';
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/privacy_policy_screen.dart';
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/about_screen.dart';
import 'package:heat_trip_flutter/features/profile/presentation/screens/menu/account_delete_screen.dart';

/// 우측에서 슬라이드 인되는 사이드 메뉴 패널
/// - showGeneralDialog 의 child 로 사용
/// - "테마설정", "약관 및 정책"은 드롭다운(ExpansionTile)로 2차 메뉴 표시
class RightSideMenuPanel extends StatelessWidget {
  final VoidCallback onClose; // 패널 닫기 콜백(보통 Navigator.pop)

  /// ✅ 로그인 여부(회원탈퇴 항목 노출 제어)
  final bool isLoggedIn;

  const RightSideMenuPanel({
    super.key,
    required this.onClose,
    this.isLoggedIn = false, // 기본값: 비로그인
  });

  /// 패널을 닫은 뒤, 하위 화면으로 네비게이션
  /// - 다이얼로그(pop)가 끝난 다음 push 해야 하기 때문에 microtask로 스케줄
  void _closeThenPush(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // 패널 먼저 닫기
    Future.microtask(() {
      // 이 콜백은 pop 이 끝난 뒤에 돈다 — 그 사이 이 위젯의 context 는 죽는다.
      // 죽은 context 로 Navigator.of 를 부르면 예외다. (#63)
      if (!context.mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => screen));
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.78; // 패널 폭

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(-8, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ===== 헤더: 타이틀 + X 버튼 =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Menu',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ===== 메뉴 리스트 =====
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // 1) 소개
                    _MenuLeaf(
                      leading: const Icon(Icons.info_outline),
                      title: '소개',
                      onTap: () => _closeThenPush(context, const AboutScreen()),
                    ),

                    // 2) 약관 및 정책 (드롭다운)
                    _MenuExpansion(
                      leading: const Icon(Icons.description_outlined),
                      title: '약관 및 정책',
                      children: [
                        _MenuLeaf(
                          title: '이용약관',
                          onTap: () =>
                              _closeThenPush(context, const TermsScreen()),
                        ),
                        _MenuLeaf(
                          title: '개인정보처리방침',
                          onTap: () => _closeThenPush(
                            context,
                            const PrivacyPolicyScreen(),
                          ),
                        ),
                      ],
                    ),

                    // 3) 의견보내기
                    _MenuLeaf(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: '의견보내기',
                      onTap: () =>
                          _closeThenPush(context, const FeedbackScreen()),
                    ),

                    // 4) 앱추천
                    _MenuLeaf(
                      leading: const Icon(Icons.share_outlined),
                      title: '앱 추천',
                      onTap: () =>
                          _closeThenPush(context, const ShareAppScreen()),
                    ),

                    // 5) 회원탈퇴 (로그인 상태에서만 노출)
                    if (isLoggedIn)
                      _MenuLeaf(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: '회원탈퇴',
                        isDestructive: true,
                        onTap: () => _closeThenPush(
                          context,
                          const AccountDeleteScreen(),
                        ),
                      ),
                  ],
                ),
              ),

              // 운영자 연락처. **하단에 고정한다** — Apple App Store Review Guideline 1.2 가
              // UGC 앱에 요구하는 네 가지 중 하나이고(필터링 · 신고 · 차단 · **공개 연락처**),
              // 없으면 심사에서 막힌다. 메뉴 안쪽에 접어 두면 "공개" 로 보기 어렵다.
              //
              // 문구를 privacy_ko.md 11항과 같은 주소로 맞춘다. 두 곳이 갈리면 어느 쪽으로
              // 문의해야 하는지 사용자가 판단하게 된다.
              const _OperatorContact(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정 하단에 고정으로 뜨는 운영자 연락처 — 이슈 #82 완료 조건 6.
///
/// 누르면 복사된다. `mailto:` 로 메일 앱을 여는 것이 더 친절해 보이지만, 메일 앱이 없는
/// 기기에서는 아무 일도 안 일어나고 사용자는 주소조차 못 얻는다. **주소를 보여 주는 것**이
/// 이 요건의 본질이라 그쪽을 택했다.
class _OperatorContact extends StatelessWidget {
  const _OperatorContact();

  /// `assets/terms/privacy_ko.md` 11항과 같은 주소여야 한다.
  static const String email = 'mn2068@naver.com';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Clipboard.setData(const ClipboardData(text: email));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('문의 주소를 복사했어요')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.mail_outline, size: 16, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '문의: $email',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              const Icon(Icons.copy_rounded, size: 14, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}

/// 드롭다운(ExpansionTile) 메뉴 공통 위젯
class _MenuExpansion extends StatelessWidget {
  final Widget? leading;
  final String title;
  final List<_MenuLeaf> children;

  const _MenuExpansion({
    required this.title,
    required this.children,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      // ExpansionTile의 기본 splash/ink 등을 최소화해서 패널 톤과 맞춤
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.only(
          left: 12 + 24,
          right: 12,
          bottom: 8,
        ),
        children: children
            .map(
              (leaf) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: leaf,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// 단일 항목(leaf) 공통 위젯
class _MenuLeaf extends StatelessWidget {
  final Widget? leading;
  final String title;
  final bool isDestructive; // 빨간 텍스트 등 파괴적 액션 강조
  final VoidCallback onTap;

  const _MenuLeaf({
    required this.title,
    required this.onTap,
    this.leading,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDestructive ? Colors.red : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.0), // 필요 시 선택 배경
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(color: fg),
                child: leading!,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 16, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

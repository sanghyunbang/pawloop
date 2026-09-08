// lib/v2/screens/settings_screen.dart
//
// 설정 — 약관 · 처리방침 · 운영자 연락처 · 회원 탈퇴. 이슈 #165.
//
// ## 이 화면이 없어서 스토어 요건 셋이 앱에서 사라져 있었다
//
// 네 화면(`TermsScreen`·`PrivacyPolicyScreen`·`AccountDeleteScreen`·운영자 연락처)이
// `features/profile/.../RightSideMenuPanel` 안에 구현돼 있었는데, **그 패널의 유일한
// 호스트 `ProfileScreen` 이 앱 어디서도 생성되지 않았다** — 유일한 흔적이
// `main_nav_layout.dart:63` 의 주석 처리된 줄이다.
//
// 그래서 실제로 보이는 `me_screen` 메뉴에는 프로필 편집·내 산책 기록·산책 통계·북마크·
// 로그아웃 여섯 줄뿐이었다.
//
// 무엇이 막히는가:
//
//  - **Apple 5.1.1(v)** — 계정 생성이 있으면 **인앱 삭제 경로**를 요구한다
//  - **Apple 1.2 / Google Play UGC** — 공개 연락처. **채팅은 이미 살아 있는 UGC 다**
//  - **Google Play** — 위치를 수집하는 앱의 인앱 처리방침 링크
//
// 그리고 `chat_terms_dialog.dart:57` 이 사용자에게 "설정 > 약관 및 정책에서 볼 수 있어요"
// 라고 말하는데 그 메뉴가 없었다 — **앱이 없는 곳을 가리키고 있었다.**
//
// ## 약관 원문은 asset 이다
//
// 예전 `TermsScreen` 은 하드코딩 템플릿이었고 `kContactEmail = 'support@example.com'`
// 같은 TODO 가 남아 있었다. 정본은 `assets/terms/*.md` 이고 회원가입 화면이 그것을
// 읽는다. 원문이 두 벌이면 어느 쪽이 사용자와 맺은 계약인지 말할 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/neighborhood_tile.dart';
import '../data/auth_state.dart';
import '../widgets/walk_reminder_tile.dart';
import 'intro_screen.dart';
import 'settings/account_delete_screen.dart';
import 'settings/legal_document_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 게스트는 지울 계정이 없다(#404). 나머지 넷은 그대로 보인다 — 약관은 스토어 요건이고
    // 내 동네·알림은 기기에만 사는 값이다.
    final guest = AuthState.isGuest;
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    _section('약관 및 정책'),
                    _card([
                      _row(context, Icons.description_outlined, '이용약관',
                          () => _open(context, LegalDocument.terms)),
                      _divider(),
                      _row(context, Icons.privacy_tip_outlined, '개인정보처리방침',
                          () => _open(context, LegalDocument.privacy)),
                      _divider(),
                      _row(context, Icons.my_location_outlined, '위치기반서비스 이용약관',
                          () => _open(context, LegalDocument.location)),
                      _divider(),
                      _row(context, Icons.campaign_outlined, '마케팅 정보 수신 동의',
                          () => _open(context, LegalDocument.marketing)),
                    ]),
                    const SizedBox(height: 18),
                    // 내 동네 (#342). 좌표가 아니라 사용자가 고른 행정동이라 위치 절이 아니라
                    // 여기 있다 — 지도와 커뮤니티가 이 값을 기준으로 삼는다.
                    _section('내 동네'),
                    _card(const [NeighborhoodTile()]),
                    const SizedBox(height: 18),
                    // 저녁 산책 알림 (#341). 푸시(#83)와 무관한 기기 안 예약이라
                    // 로그인·토큰과 상관이 없다.
                    _section('알림'),
                    _card(const [WalkReminderTile()]),
                    const SizedBox(height: 18),
                    // 첫 실행 소개는 한 번만 나온다(#323). 닫아 버린 안내를 나중에 다시
                    // 찾을 수 있어야 한다 — 그 자리가 여기다.
                    _section('앱'),
                    _card([
                      _row(context, Icons.auto_awesome_outlined, '앱 소개 다시 보기',
                          () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => IntroScreen(
                                    replay: true,
                                    onDone: () => Navigator.of(context).maybePop(),
                                  )))),
                    ]),
                    if (!guest) ...[
                      const SizedBox(height: 18),
                      _section('계정'),
                      _card([
                        _row(
                          context,
                          Icons.person_remove_outlined,
                          '회원 탈퇴',
                          () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const AccountDeleteScreen())),
                          danger: true,
                        ),
                      ]),
                    ],
                    const SizedBox(height: 24),
                    // 하단 고정 — #82 완료 조건 6 이 정한 자리다.
                    const OperatorContact(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _open(BuildContext context, LegalDocument doc) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LegalDocumentScreen(document: doc)),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x66FFFFFF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.arrow_back, size: 20, color: T.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          const Text('설정',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
        ]),
      );

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
      );

  Widget _card(List<Widget> children) => ClipRRect(
        borderRadius: BorderRadius.circular(T.radius),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      );

  Widget _divider() =>
      Container(height: 1, color: const Color(0x148C7BFF));

  Widget _row(BuildContext context, IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Icon(icon,
                size: 19,
                color: danger ? const Color(0xFFD9534F) : const Color(0xA8463C64)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: danger ? const Color(0xFFD9534F) : T.textPrimary)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ),
      );
}

/// 설정 하단에 고정으로 뜨는 운영자 연락처 — 이슈 #82 완료 조건 6.
///
/// 누르면 **복사된다.** `mailto:` 로 메일 앱을 여는 것이 더 친절해 보이지만, 메일 앱이
/// 없는 기기에서는 아무 일도 안 일어나고 사용자는 **주소조차 못 얻는다.** 주소를 보여
/// 주는 것이 이 요건의 본질이라 그쪽을 택했다.
///
/// 예전에는 `right_side_menu_panel.dart` 안의 private 클래스였고, 그 패널이 도달 불가라
/// **연락처도 함께 사라져 있었다.**
class OperatorContact extends StatelessWidget {
  const OperatorContact({super.key});

  /// `assets/terms/privacy_ko.md` 11항과 **같은 주소여야 한다.**
  ///
  /// 두 곳이 갈리면 어느 쪽으로 문의해야 하는지 사용자가 판단하게 된다.
  static const String email = 'mn2068@naver.com';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(const ClipboardData(text: email));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('연락처를 복사했어요'),
              duration: Duration(milliseconds: 1400),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('문의 · 신고',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.mail_outline, size: 15, color: T.textMuted),
                const SizedBox(width: 6),
                Text(email,
                    style: const TextStyle(fontSize: 13, color: T.textSecondary)),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 13, color: T.textMuted),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

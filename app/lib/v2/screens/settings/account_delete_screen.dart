// lib/v2/screens/settings/account_delete_screen.dart
//
// 회원 탈퇴 — 이슈 #165.
//
// ## 이 화면은 있었지만 앱에서 닿을 수 없었다
//
// `features/profile/.../menu/` 에 있었고, 유일한 호스트인 `RightSideMenuPanel` 을 여는
// `ProfileScreen` 이 **주석 처리된 줄에만** 있었다(`main_nav_layout.dart:63`). 즉
// **앱 안에서 계정을 지울 방법이 없었다.**
//
// Apple App Store Review Guideline 5.1.1(v)는 계정 생성이 있는 앱에 **인앱 삭제 경로**를
// 요구한다. 이 앱은 소셜·이메일 두 가지로 계정을 만든다.
//
// 그래서 v2 설정(`settings_screen.dart`)으로 옮겼다. 파일 위치만 바뀌었고 삭제 흐름은
// 그대로다 — `context.goNamed` 가 동작하는 것은 앱 루트가 여전히 `MaterialApp.router` 이기
// 때문이다(`main.dart:142`).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';
import 'package:heat_trip_flutter/v2/data/auth_state.dart';

class AccountDeleteScreen extends StatelessWidget {
  const AccountDeleteScreen({super.key});

  static const kDanger = Colors.red;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54, // 배경 딤 처리
      builder: (_) => const _DeleteConfirmDialog(),
    );

    if (ok != true || !context.mounted) return;

    final repo = AuthRepositoryImpl();
    final token = await SecureTokenStore.instance.readAccessToken();

    if (token == null) {
      // 서버에 부를 세션 자체가 없다 — 로컬만 정리한다.
      await AuthState.clearLocalSession();
      if (context.mounted) context.goNamed('login');
      return;
    }

    final success = await repo.deleteMyAccount();

    if (!context.mounted) return;

    if (success) {
      // 계정이 지워졌으므로 `POST /auth/logout` 은 401 이다 — 로컬만 정리한다 (#12).
      await AuthState.clearLocalSession();
      // 위 가드(:34)는 deleteMyAccount 뒤의 것이다. 세션 정리도 await 이라
      // 그 사이에 화면이 사라졌을 수 있다. 탈퇴와 토큰 삭제는 이미 끝났으므로
      // 여기서 돌아가도 잃는 것은 안내와 화면 이동뿐이다. (#63)
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴가 완료되었습니다.')),
      );
      // **어디로 갈지는 라우터가 정한다. 여기서는 길만 터 준다.**
      //
      // 예전에는 `goNamed('start')` 로 레거시 셸에 보냈고, 그러면 탈퇴한 사람이
      // Heat Trip 로고가 붙은 **다른 제품**에 착지했다 (#184).
      //
      // 그렇다고 아무것도 안 하면 화면이 **여기 그대로 남는다.** 실제로 그랬다 —
      // 계정은 지워졌는데(로그인이 401) 탈퇴 화면이 그대로였다.
      //
      // 이유는 이 화면이 go_router 의 라우트가 아니라 그 위에 `Navigator.push` 로
      // 얹혀 있기 때문이다(`me_screen` → `settings_screen` → 여기, 셋 다
      // `MaterialPageRoute`). `clearLocalSession` 이 상태를 내리면 라우터는 자기
      // 스택을 `/auth/login` 으로 바꾸지만, **그 위에 얹힌 화면들이 그것을 덮는다.**
      //
      // 그래서 얹힌 것만 걷어낸다. 그러면 라우터가 이미 바꿔 둔 화면이 드러난다.
      // 목적지를 여기서 정하지 않으므로 규칙은 여전히 한 곳(`authRedirect`)에 있다.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원탈퇴')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('주의', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // 예전 문구: "탈퇴 시 모든 데이터가 삭제되며 복구할 수 없습니다."
            //
            // 그건 틀린 말이 됐다 (이슈 #82). 채팅 메시지는 users 로 CASCADE 하지 않아서
            // 탈퇴해도 받은 사람들의 대화방에 남는다 — 지우면 대답만 있고 질문이 없는
            // 대화가 되고, 신고 근거도 함께 사라진다.
            //
            // 지키지 못할 약속을 화면에 띄우는 것이 정책 위반보다 더 위험하다.
            //
            // **커뮤니티가 붙으면서 같은 약속이 또 한 번 틀렸다** (#253). post·comment·
            // reaction 의 user_id 가 ON DELETE SET NULL 이라(14_community.sql:212·225·236)
            // 글도 댓글도 반응도 남는다. 위 문장이 적어 둔 원칙이 바로 이 자리에서
            // 두 번째로 깨진 것이다 — 기능이 늘 때마다 이 문구를 다시 봐야 한다.
            const Text(
              '탈퇴하면 계정·프로필·반려동물 정보와 산책 기록이 삭제되며 '
              '복구할 수 없습니다.\n\n'
              '다만 다른 분의 기록이기도 한 것은 남습니다. '
              '이미 보낸 채팅 메시지는 받은 분들의 대화방에, '
              '커뮤니티에 쓴 글·댓글·반응은 커뮤니티에 남고, '
              '작성자는 \'알 수 없음\'으로 표시됩니다.\n\n'
              '지우려면 탈퇴하기 전에 직접 삭제해 주세요.',
              style: TextStyle(height: 1.5),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDanger,
                  foregroundColor: Colors.white, // 텍스트/아이콘 흰색
                ),
                onPressed: () => _confirmDelete(context),
                child: const Text('정말로 탈퇴하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===== 커스텀 탈퇴 확인 다이얼로그 =====
class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog();

  static const Color kDanger = Colors.red;
  static const Color kStroke = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 경고 아이콘
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0x1AF44336), // 연한 레드 배경
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_rounded, color: kDanger, size: 36),
            ),
            const SizedBox(height: 14),

            const Text(
              '정말 탈퇴하시겠어요?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),

            // 위 화면과 같은 취지여야 한다 (#82). 확인 창에서만 "모든 데이터" 라고 하면
            // 마지막으로 읽는 문장이 틀린 말이 된다.
            const Text(
              '탈퇴하면 계정·프로필·반려동물 정보와 내가 남긴 기록이\n'
              '삭제되며 복구할 수 없습니다.\n'
              '이미 보낸 채팅 메시지는 대화방에 남습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 20),

            const Divider(height: 1, color: kStroke),
            const SizedBox(height: 12),

            Row(
              children: [
                // 취소(외곽)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kStroke),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                // 탈퇴(위험)
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDanger,
                      foregroundColor: Colors.white, // 텍스트/아이콘 흰색
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('탈퇴하기'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

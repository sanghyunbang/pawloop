// lib/features/profile/presentation/account_delete_screen.dart
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
      context.goNamed('start');
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
            const Text(
              '탈퇴하면 계정·프로필·반려동물 정보와 내가 남긴 기록이 삭제되며 '
              '복구할 수 없습니다.\n\n'
              '이미 보낸 채팅 메시지는 받은 분들의 대화방에 남고, '
              '보낸 사람은 \'알 수 없음\'으로 표시됩니다.',
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

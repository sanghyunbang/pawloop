import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 채팅에 처음 들어갈 때 뜨는 동의 창 — 이슈 #82 완료 조건 6.
///
/// ## 무엇을 말하는가
///
/// 약관 이름만 나열하지 않는다. **이 화면에서 실제로 일어나는 일**을 적는다 — 신고하면
/// 어떻게 되는지, 가리기가 삭제와 어떻게 다른지, 탈퇴해도 메시지가 남는다는 것.
///
/// 나열만 하면 사용자는 읽지 않고 누르고, 나중에 "그런 말 없었다" 가 된다. 특히 **탈퇴해도
/// 메시지가 남는다**는 것은 여기서 한 번은 말해야 하는 사실이다.
///
/// ## 취소가 있다
///
/// 동의하지 않으면 채팅에 안 들어간다. **강제로 동의시키지 않는다** — 그러면 그건 동의가
/// 아니라 통보다. 방을 못 쓰게 되지만 앱의 나머지는 그대로 쓸 수 있다.
class ChatTermsDialog extends StatelessWidget {
  const ChatTermsDialog({super.key});

  /// 동의했으면 `true`. 취소하거나 바깥을 눌렀으면 `false`.
  static Future<bool> show(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      // 바깥을 눌러 닫는 것을 막지 않는다. 막으면 "읽을 때까지 못 나간다" 가 되는데,
      // 그건 동의를 받는 것이 아니라 가두는 것이다.
      builder: (_) => const ChatTermsDialog(),
    );
    return agreed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('대화를 시작하기 전에', style: TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '함께 쓰는 공간이라 몇 가지를 먼저 알려 드려요.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: T.textPrimary),
            ),
            SizedBox(height: 14),
            _Line('불쾌한 메시지는 길게 눌러 신고할 수 있어요. '
                '신고한 사실은 상대에게 알리지 않습니다.'),
            _Line('특정 사람의 메시지를 가릴 수 있어요. '
                '가려도 삭제되지 않고 다른 분 화면에는 그대로 남습니다.'),
            _Line('방장은 멤버를 내보낼 수 있어요. '
                '내보내면 초대코드를 다시 받아도 들어올 수 없습니다.'),
            _Line('탈퇴해도 이미 보낸 메시지는 대화방에 남고, '
                '보낸 사람은 "알 수 없음"으로 표시됩니다.'),
            SizedBox(height: 12),
            Text(
              '자세한 내용은 설정 > 약관 및 정책에서 볼 수 있어요.',
              style: TextStyle(fontSize: 12, color: T.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('나중에'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('동의하고 시작'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 8),
          child: Icon(Icons.circle, size: 4, color: T.textMuted),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.5, color: T.textSecondary),
          ),
        ),
      ]),
    );
  }
}

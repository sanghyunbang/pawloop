// 가족 채팅 첫 진입 규칙 대화상자 — 필요한 순간에, 짧게 (#82 · #330).
//
// 전에는 네 문단(신고 · 가리기 · 내보내기 · 탈퇴 뒤 표시)을 한꺼번에 보여 줬다. 걸어 보니
// 길었다(#330). 지금은 **두 줄 요약**이 기본이고 "자세히" 를 누르면 네 줄이 펼쳐진다.
// 전문은 설정 > 약관 및 정책에 있다.
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class ChatTermsDialog extends StatefulWidget {
  const ChatTermsDialog({super.key});

  /// 두 줄 요약. 탈퇴 뒤에도 메시지가 남는다는 것은 접힌 상태에서도 말한다 —
  /// 나중에 "그런 말 없었다" 가 안 되게.
  static const String summary =
      '함께 쓰는 공간이에요. 불쾌한 메시지는 길게 눌러 신고하거나 가릴 수 있고, '
      '탈퇴해도 보낸 메시지는 대화방에 남아요.';

  /// "자세히" 를 누르면 펼쳐지는 네 줄.
  static const List<String> details = [
    '불쾌한 메시지는 길게 눌러 신고할 수 있어요. 신고한 사실은 상대에게 알리지 않습니다.',
    '특정 사람의 메시지를 가릴 수 있어요. 가려도 삭제되지 않고 다른 분 화면에는 그대로 남습니다.',
    '방장은 멤버를 내보낼 수 있어요. 내보내면 초대코드를 다시 받아도 들어올 수 없습니다.',
    '탈퇴해도 이미 보낸 메시지는 대화방에 남고, 보낸 사람은 "알 수 없음"으로 표시됩니다.',
  ];

  static Future<bool> show(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChatTermsDialog(),
    );
    return agreed ?? false;
  }

  @override
  State<ChatTermsDialog> createState() => _ChatTermsDialogState();
}

class _ChatTermsDialogState extends State<ChatTermsDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('대화를 시작하기 전에', style: TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              ChatTermsDialog.summary,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: T.textPrimary),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(_expanded ? '접기' : '자세히', style: const TextStyle(fontSize: 13)),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              for (final line in ChatTermsDialog.details) _Line(line),
              const SizedBox(height: 4),
              const Text(
                '자세한 내용은 설정 > 약관 및 정책에서 볼 수 있어요.',
                style: TextStyle(fontSize: 12, color: T.textMuted),
              ),
            ],
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

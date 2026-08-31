import 'package:flutter/material.dart';

import '../data/chat_repository.dart';
import '../theme/app_tokens.dart';

/// 메시지를 길게 눌렀을 때 뜨는 것 — 이슈 #82 완료 조건 6.
///
/// ## 왜 신고와 가리기를 한 화면에 두는가
///
/// 사용자가 이 순간 하고 싶은 것은 **"이 사람 때문에 불편하다"** 하나인데, 그것을 푸는
/// 방법이 둘이다. 신고는 운영자에게 알리는 것이고 가리기는 내 화면을 정리하는 것이다.
/// 화면을 나누면 사용자가 무엇을 눌러야 하는지 매번 판단해야 한다.
///
/// ## 자동으로 묶지 않는다
///
/// 신고 화면에 "이 사람 가리기" 체크박스가 있지만 **기본값이 꺼져 있다.** 카카오는 신고하면
/// 자동 차단이고 "신고 후에는 취소할 수 없습니다" 라는 경고까지 단다
/// (https://cs.kakao.com/helps_html/1073199401) — 가족방에서 그건 되돌릴 수 없는 사고가 된다.
///
/// 서버도 묶지 않는다. 켰으면 앱이 `POST /api/chat/blocks` 를 **따로** 부른다.
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.senderName,
    required this.hiddenByBlock,
    required this.canRemoveMember,
  });

  final String senderName;

  /// 이미 가려 둔 사람인가. 그러면 "가리기" 대신 "가리기 해제" 를 보여 준다.
  final bool hiddenByBlock;

  /// 내가 이 방의 방장인가. 강퇴는 방장만 할 수 있다.
  final bool canRemoveMember;

  static Future<MessageAction?> show(
    BuildContext context, {
    required String senderName,
    required bool hiddenByBlock,
    required bool canRemoveMember,
  }) {
    return showModalBottomSheet<MessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MessageActionsSheet(
        senderName: senderName,
        hiddenByBlock: hiddenByBlock,
        canRemoveMember: canRemoveMember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // Material 로 감싼다. Container + BoxDecoration 으로 배경을 칠하면 ListTile 이
      // 자기 잉크를 가장 가까운 Material 에 그리는데 그 DecoratedBox 가 그것을 덮는다 —
      // 프레임워크가 경고로 잡아 준다.
      child: Container(
        margin: const EdgeInsets.all(12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  senderName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary),
                ),
              ),
            ]),
          ),
          _tile(
            context,
            icon: Icons.flag_outlined,
            label: '신고하기',
            value: MessageAction.report,
          ),
          _tile(
            context,
            icon: hiddenByBlock ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            label: hiddenByBlock ? '가리기 해제' : '이 사람 가리기',
            value: hiddenByBlock ? MessageAction.unblock : MessageAction.block,
          ),
          if (canRemoveMember)
            _tile(
              context,
              icon: Icons.person_remove_outlined,
              label: '방에서 내보내기',
              value: MessageAction.removeMember,
              danger: true,
            ),
          const SizedBox(height: 6),
        ]),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required MessageAction value,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFD64545) : T.textPrimary;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

/// 시트에서 고른 것.
enum MessageAction { report, block, unblock, removeMember }

/// 신고 사유를 고르는 화면 — 이슈 #82.
///
/// ## 사유가 필수인 이유
///
/// 분류가 있어야 운영자가 **세어서 볼 수 있다.** 자유 서술만 받으면 같은 종류의 신고가
/// 열 가지 표현으로 흩어져 "이 방에 성적 내용 신고가 몇 건인가" 를 물을 수 없다.
///
/// 어휘의 출처는 계약이고([ChatReportReason]), 목록에 없는 값을 보내면 서버가 400 을 낸다.
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.senderName, required this.messageCount});

  final String senderName;

  /// 함께 신고할 메시지 수. **최대 3개** 이고 그 판정은 서버가 한다.
  final int messageCount;

  static Future<ReportChoice?> show(
    BuildContext context, {
    required String senderName,
    required int messageCount,
  }) {
    return showModalBottomSheet<ReportChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ReportSheet(senderName: senderName, messageCount: messageCount),
      ),
    );
  }

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ChatReportReason? _reason;
  final TextEditingController _memo = TextEditingController();

  /// **기본값은 꺼짐이다.** 신고에 자동 차단을 묶으면 가족방에서 되돌릴 수 없는 사고가 된다.
  bool _alsoBlock = false;

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // Material 인 이유는 MessageActionsSheet 와 같다 — CheckboxListTile 도 잉크를
      // 가장 가까운 Material 에 그린다.
      child: Container(
        margin: const EdgeInsets.all(12),
        child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${widget.senderName} 님을 신고합니다',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '메시지 ${widget.messageCount}개가 함께 접수됩니다. 신고한 사실은 상대에게 알리지 않습니다.',
            style: const TextStyle(fontSize: 12, height: 1.4, color: T.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in ChatReportReason.values)
                ChoiceChip(
                  label: Text(reason.label, style: const TextStyle(fontSize: 12.5)),
                  selected: _reason == reason,
                  onSelected: (_) => setState(() => _reason = reason),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _memo,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: '무슨 일이 있었는지 적어 주세요 (선택)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          CheckboxListTile(
            value: _alsoBlock,
            onChanged: (v) => setState(() => _alsoBlock = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('이 사람의 메시지를 가리기',
                style: TextStyle(fontSize: 13, color: T.textPrimary)),
            subtitle: const Text('내 화면에서만 접힙니다. 삭제가 아니에요',
                style: TextStyle(fontSize: 11.5, color: T.textMuted)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // 사유를 안 고르면 못 누른다. 서버도 400 으로 막지만, 눌러 보고서야 아는 것은
              // 실패를 겪게 하는 것이라 여기서 먼저 막는다.
              onPressed: _reason == null
                  ? null
                  : () => Navigator.of(context).pop(
                        ReportChoice(
                          reason: _reason!,
                          memo: _memo.text,
                          alsoBlock: _alsoBlock,
                        ),
                      ),
              child: const Text('신고하기'),
            ),
          ),
        ]),
        ),
        ),
      ),
    );
  }
}

/// 신고 화면에서 고른 것.
class ReportChoice {
  const ReportChoice({required this.reason, required this.memo, required this.alsoBlock});

  final ChatReportReason reason;
  final String memo;

  /// 함께 가릴 것인가. **신고와 별개의 요청이다** — 서버가 묶어 주지 않는다.
  final bool alsoBlock;
}

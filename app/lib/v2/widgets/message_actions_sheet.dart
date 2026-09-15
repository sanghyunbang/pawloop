import 'package:flutter/material.dart';

import '../data/chat_repository.dart';
import '../domain/chat_reaction.dart';
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
/// 서버도 묶지 않는다. 켰으면 앱이 `POST /api/blocks` 를 **따로** 부른다.
///
/// ## 답장이 맨 위다 (#452)
///
/// 길게 눌러서 가장 자주 하는 일은 신고가 아니라 **답장**이다 — 카카오톡 · 인스타그램 DM 이 같은
/// 메뉴의 첫 줄에 둔다. 내 말에도 남의 말에도 있고, 지워진 말에는 없다([canReply]).
///
/// ## 반응은 그보다 위, 줄 하나다 (#452)
///
/// 다섯을 목록의 줄로 늘어놓으면 시트가 화면을 덮는다. 카카오톡 · 인스타그램 DM 이 둘 다 **가로 한
/// 줄**로 두고, 그래서 한 번의 탭으로 끝난다 — 길게 누른 손가락이 그대로 움직여 닿는 자리다.
///
/// 이미 누른 것은 **테두리로 표시**하고, 그것을 다시 누르면 취소다([myKinds]). 끄기를 따로 두지
/// 않는 것은 같은 자리에서 켰기 때문이다 — 서버의 켜기·끄기가 갈라져 있어 앱이 어느 쪽인지
/// 정해서 부른다(재시도가 반응을 되돌리지 않는 이유, `ChatRepository.react`).
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.senderName,
    required this.hiddenByBlock,
    required this.canRemoveMember,
    this.isMine = false,
    this.canReply = true,
    this.canReact = true,
    this.myKinds = const {},
  });

  final String senderName;

  /// 이미 가려 둔 사람인가. 그러면 "가리기" 대신 "가리기 해제" 를 보여 준다.
  final bool hiddenByBlock;

  /// 내가 이 방의 방장인가. 강퇴는 방장만 할 수 있다.
  final bool canRemoveMember;

  /// 내가 보낸 메시지인가. 그러면 신고·가리기·내보내기는 뜻이 없고 **삭제** 하나뿐이다(#197).
  final bool isMine;

  /// 답장(#452)을 보여 줄 것인가 — 지워진 메시지에는 없다.
  final bool canReply;

  /// 반응 줄(#452)을 보여 줄 것인가 — 지워진 메시지에는 없다(서버도 409 로 막는다).
  final bool canReact;

  /// 내가 이미 누른 종류들 — 계약의 값 그대로. 테두리로 표시하고, 다시 누르면 취소다.
  final Set<String> myKinds;

  static Future<MessageChoice?> show(
    BuildContext context, {
    required String senderName,
    required bool hiddenByBlock,
    required bool canRemoveMember,
    bool isMine = false,
    bool canReply = true,
    bool canReact = true,
    Set<String> myKinds = const {},
  }) {
    return showModalBottomSheet<MessageChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MessageActionsSheet(
        senderName: senderName,
        hiddenByBlock: hiddenByBlock,
        canRemoveMember: canRemoveMember,
        isMine: isMine,
        canReply: canReply,
        canReact: canReact,
        myKinds: myKinds,
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
          // 짧은 화면·큰 글씨에서는 스크롤한다. 반응 줄이 생기면서 줄 수가 늘어 낮은 창에서
          // 17px 이 잘렸다(위젯 테스트가 잡았다) — 잘린 자리는 "방에서 내보내기" 였다.
          child: SingleChildScrollView(
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
          if (canReact) _reactionRow(context),
          if (canReply)
            _tile(
              context,
              icon: Icons.reply_rounded,
              label: '답장',
              value: MessageAction.reply,
            ),
          if (isMine)
            _tile(
              context,
              icon: Icons.delete_outline,
              label: '이 메시지 삭제',
              value: MessageAction.delete,
              danger: true,
            )
          else ...[
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
          ],
          const SizedBox(height: 6),
        ]),
        ),
        ),
      ),
    );
  }

  /// 반응 다섯 — 가로 한 줄. 이미 누른 것은 테두리가 있고, 그것을 다시 누르면 취소다.
  Widget _reactionRow(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final kind in ChatReactionKind.values)
              Semantics(
                button: true,
                selected: myKinds.contains(kind.wire),
                label: kind.label,
                child: InkResponse(
                  key: Key('reaction-pick-${kind.wire}'),
                  radius: 26,
                  onTap: () => Navigator.of(context).pop(MessageChoice.react(kind.wire)),
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: myKinds.contains(kind.wire) ? T.accentSoft : Colors.transparent,
                      border: myKinds.contains(kind.wire)
                          ? Border.all(color: T.accent, width: 1.4)
                          : null,
                    ),
                    child: Text(kind.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
          ],
        ),
      );

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
      onTap: () => Navigator.of(context).pop(MessageChoice(value)),
    );
  }
}

/// 시트에서 고른 것.
enum MessageAction { react, reply, report, block, unblock, removeMember, delete }

/// 시트가 돌려주는 것 — 반응이면 [kind] 가 함께 온다.
///
/// 열거값 하나로는 "어느 반응인가" 를 실을 수 없다. 종류마다 열거값을 늘리면
/// (`reactLike`·`reactHeart`…) 서버가 종류를 하나 늘릴 때마다 앱의 분기가 늘어난다.
class MessageChoice {
  const MessageChoice(this.action, {this.kind});

  const MessageChoice.react(String kind) : this(MessageAction.react, kind: kind);

  final MessageAction action;

  /// 계약의 `ChatReactionKind` 값. [MessageAction.react] 일 때만 있다.
  final String? kind;
}

/// 신고 사유를 고르는 화면 — 이슈 #82.
///
/// ## 사유가 필수인 이유
///
/// 분류가 있어야 운영자가 **세어서 볼 수 있다.** 자유 서술만 받으면 같은 종류의 신고가
/// 열 가지 표현으로 흩어져 "이 방에 성적 내용 신고가 몇 건인가" 를 물을 수 없다.
///
/// 어휘의 출처는 계약이고([ChatReportReason]), 목록에 없는 값을 보내면 서버가 400 을 낸다.
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.senderName,
    required this.subject,
    this.canBlock = true,
  });

  final String senderName;

  /// 무엇이 함께 접수되는지 한 줄로. 채팅은 "메시지 3개", 커뮤니티는 "이 글" 이다.
  final String subject;

  /// 가리기 체크박스를 보일 것인가.
  ///
  /// **지금은 채팅도 커뮤니티도 `true` 다.** #166 이 가리기를 chat 밖의 공용 모듈로
  /// 올리면서 커뮤니티에도 붙였다(`post_detail_screen` 이 `canBlock: true` 를 넘긴다).
  ///
  /// 그래도 이 인자를 남겨 둔다 — 받는 척하는 칸이 화면에 있으면 사용자가 그것을
  /// 믿는다. 가리기가 없는 자리가 다시 생기면 그 자리에서 `false` 를 넘겨야 한다.
  /// 채팅 신고가 같은 이유로 예전 초안의 `alsoBlock` 을 계약에서 뺐다.
  final bool canBlock;

  static Future<ReportChoice?> show(
    BuildContext context, {
    required String senderName,
    required String subject,
    bool canBlock = true,
  }) {
    return showModalBottomSheet<ReportChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ReportSheet(
            senderName: senderName, subject: subject, canBlock: canBlock),
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
            '${widget.subject}이(가) 함께 접수됩니다. 신고한 사실은 상대에게 알리지 않습니다.',
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
          if (widget.canBlock)
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

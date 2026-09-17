// 가족 채팅 규칙 대화상자 — 필요한 순간에, 짧게 (#82 · #330 · #682).
//
// 전에는 네 문단(신고 · 가리기 · 내보내기 · 탈퇴 뒤 표시)을 한꺼번에 보여 줬다. 걸어 보니
// 길었다(#330). 지금은 **두 줄 요약**이 기본이고 "자세히" 를 누르면 네 줄이 펼쳐진다.
// 전문은 설정 > 약관 및 정책에 있다.
//
// ## 주의 · 제재 문구는 접지 않는다 (#682)
//
// 원스토어 검증 가이드라인이 채팅 기능에 **피해 예방 주의 문구와 제재 안내**를 요구한다.
// #330 의 "짧게" 를 여기서만 양보한 이유다 — 접어 두면 읽지 않는 사람에게는 없는 문구고,
// 심사자에게도 안 보인다. 그래서 [ChatTermsDialog.safety] 세 줄은 **처음부터 펼쳐진 채**
// 요약 바로 밑에 있고, 기능 안내 네 줄만 "자세히" 뒤에 남는다.
//
// 문구의 근거:
//
//  * 금전 · 개인정보 요구 — 이용약관 제6조 2)(타인의 권리 침해) · 제4조 2항(명의 도용 시
//    이용 제한 및 법적 책임). 로맨스스캠 · 계정 도용이 채팅으로 들어오는 길이다.
//  * 불법 촬영물 — 「성폭력범죄의 처벌 등에 관한 특례법」 제14조(카메라 등을 이용한 촬영).
//  * 통신으로 하는 성적 괴롭힘 — 같은 법 제13조(통신매체를 이용한 음란행위).
//  * 아동 · 청소년 성착취물 — 「아동·청소년의 성보호에 관한 법률」 제11조.
//    셋 다 형이 법마다 달라 **액수와 형량은 적지 않는다** — 틀린 숫자를 적느니 "관련 법에
//    따라 처벌될 수 있다" 고만 말한다.
//  * 제재의 범위 — 이용약관 제7조 3항(위반이 명백한 콘텐츠의 삭제 · 비노출) · 제9조 1항
//    (약관 또는 법령 위반 시 이용 정지 또는 해지). **약관에 없는 제재를 지어내지 않는다.**
//
// ## 방 안에서 다시 보기 (#682)
//
// 입구에서 한 번 뜨고 마는 안내는 사고가 나는 순간에는 이미 사라진 뒤다. 채팅방 머리말의
// 안내 버튼이 [ChatTermsDialog.showAgain] 으로 같은 문구를 다시 띄운다. 그때는 동의를
// 다시 받는 자리가 아니라 **읽는 자리**라 버튼이 "닫기" 하나고, 네 줄도 처음부터 펼쳐 둔다.
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class ChatTermsDialog extends StatefulWidget {
  const ChatTermsDialog({super.key, this.reviewOnly = false});

  /// 방 안에서 다시 보는 중인가. 동의를 받는 자리가 아니면 "닫기" 하나만 둔다 —
  /// 이미 동의한 사람에게 "동의하고 시작" 을 또 내밀면 무엇에 동의하는 것인지 모호해진다.
  final bool reviewOnly;

  /// 두 줄 요약. 탈퇴 뒤에도 메시지가 남는다는 것은 접힌 상태에서도 말한다 —
  /// 나중에 "그런 말 없었다" 가 안 되게.
  static const String summary =
      '함께 쓰는 공간이에요. 불쾌한 메시지는 길게 눌러 신고하거나 가릴 수 있고, '
      '탈퇴해도 보낸 메시지는 대화방에 남아요.';

  /// 주의 블록의 머리말.
  static const String safetyTitle = '안전을 위해 꼭 지켜 주세요';

  /// **접지 않는 세 줄** — 피해 예방 주의와 제재 안내 (#682). 근거는 파일 머리말에 있다.
  static const List<String> safety = [
    '금전이나 개인정보(계좌번호·주민등록번호 등)를 요구받으면 응하지 마시고 신고해 주세요.',
    '불법 촬영물, 성적 괴롭힘, 아동·청소년 성착취물은 금지되며 관련 법에 따라 처벌될 수 있습니다.',
    '위반한 메시지는 삭제·비노출되고, 이용이 제한되거나 계정이 정지·해지될 수 있어요.',
  ];

  /// "자세히" 를 누르면 펼쳐지는 네 줄.
  static const List<String> details = [
    '불쾌한 메시지는 길게 눌러 신고할 수 있어요. 신고한 사실은 상대에게 알리지 않습니다.',
    '특정 사람의 메시지를 가릴 수 있어요. 가려도 삭제되지 않고 다른 분 화면에는 그대로 남습니다.',
    '방장은 멤버를 내보낼 수 있어요. 내보내면 초대코드를 다시 받아도 들어올 수 없습니다.',
    '탈퇴해도 이미 보낸 메시지는 대화방에 남고, 보낸 사람은 "알 수 없음"으로 표시됩니다.',
  ];

  /// 첫 진입 — 동의를 받는다. 동의하지 않으면 `false`.
  static Future<bool> show(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChatTermsDialog(),
    );
    return agreed ?? false;
  }

  /// 방 안에서 다시 보기 — 읽기만 한다. 동의 여부를 바꾸지 않으므로 돌려줄 값이 없다.
  static Future<void> showAgain(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ChatTermsDialog(reviewOnly: true),
    );
  }

  @override
  State<ChatTermsDialog> createState() => _ChatTermsDialogState();
}

class _ChatTermsDialogState extends State<ChatTermsDialog> {
  /// 다시 보러 온 사람은 무언가를 찾으러 온 것이다 — 그 앞에서 또 접어 두지 않는다.
  late bool _expanded = widget.reviewOnly;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reviewOnly ? '채팅 이용 안내' : '대화를 시작하기 전에',
          style: const TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              ChatTermsDialog.summary,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: T.textPrimary),
            ),
            const SizedBox(height: 10),
            const _SafetyBox(),
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
      actions: widget.reviewOnly
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ]
          : [
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

// 주의 상자의 앰버 — 상태색(앰버 주의)은 토큰이 아니라 그대로 쓴다. `app_tokens.dart`
// 머리말의 규칙이다("카테고리색과 상태색은 토큰이 아니라 그대로다").
const Color _warnBg = Color(0xFFFFF7E8);
const Color _warnBorder = Color(0xFFF0DFBC);
const Color _warnHead = Color(0xFF8A6100);

/// 주의 · 제재 세 줄을 담은 상자 (#682).
///
/// 요약과 같은 흐름에 두면 눈이 미끄러져 지나가므로 바탕색으로 한 번 멈추게 한다.
class _SafetyBox extends StatelessWidget {
  const _SafetyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _warnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warnBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.shield_outlined, size: 15, color: _warnHead),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                ChatTermsDialog.safetyTitle,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _warnHead),
              ),
            ),
          ]),
          const SizedBox(height: 7),
          for (final line in ChatTermsDialog.safety) _Line(line, dense: true),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.dense = false});

  final String text;

  /// 주의 상자 안에서 쓰는 촘촘한 줄 — 세 줄이 더 붙는데도 1080×2400 에서
  /// 스크롤이 생기지 않아야 한다(#330 완료 조건).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 5 : 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.only(top: dense ? 5.5 : 6, right: dense ? 7 : 8),
          child: Icon(Icons.circle, size: 4, color: dense ? _warnHead : T.textMuted),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: dense ? 12.5 : 13,
              height: dense ? 1.45 : 1.5,
              color: T.textSecondary,
            ),
          ),
        ),
      ]),
    );
  }
}

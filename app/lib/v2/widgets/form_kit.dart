// 폼 부품 한 벌 — 이슈 #445. design-system.md §5.5(버튼)·§5.6(칩)·§4(형태) 를 코드로 둔다.
//
// ## 왜 한 벌인가
//
// 홈·커뮤니티·크루 홈은 오라 배경·글래스 카드·SIG 그라데이션으로 짜였는데, 그 뒤에 만든
// 시트들(일정 적기·아이 등록·크루 만들기)이 머티리얼 기본 위젯(`OutlinedButton` · `OutlineInputBorder`
// · 색 없는 `FilledButton`)을 그대로 써서 같은 앱 안에 두 가지 결이 섞였다 — 사장님이 "너무
// 구리다" 고 짚은 것이 그것이다. 체계 문서가 "칩·섹션헤더 공용 위젯화는 post-MVP" 라고 미뤄 둔
// 일을 여기서 한다. 화면마다 다시 그리면 결이 또 갈린다.
//
// ## 버튼은 머티리얼 버튼을 **감싼다**, 대신하지 않는다
//
// [PrimaryButton] 은 그라데이션 상자 안에 투명한 `FilledButton` 을 둔다. 그래서 잉크 물결·포커스·
// 스크린리더가 머티리얼 그대로이고, 테스트의 `find.widgetWithText(FilledButton, '저장')` 도 그대로
// 산다. 색만 우리 것이다.
//
// ## 무엇이 있나
//
// - [SheetFrame] — 바텀시트 틀: 바탕색 · 손잡이 · 제목 · 한 줄 설명 · 키보드 여백 · SafeArea · 스크롤
// - [PrimaryButton] · [SecondaryButton] — §5.5 그대로(높이 52 · radius 16 · 그라데이션 / 흰 반투명)
// - [PickerButton] — 날짜·시각처럼 "눌러서 고르는 값" 을 보여 주는 흰 상자
// - [GlassField] — 흰 채움 + 옅은 테두리의 입력칸(`course_save_sheet` 의 것). 머티리얼 아웃라인이 아니다
// - [PillChip] — 알약 칩. 선택하면 강조색으로 채운다
// - [FormLabel] — 칸 이름 한 줄
// - [SigFab] — 산책 버튼과 같은 모양의 둥근 그라데이션 버튼. 화면의 "새로 적기"
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 바텀시트의 틀. 시트마다 손잡이·제목·여백을 다시 그리지 않는다.
class SheetFrame extends StatelessWidget {
  final String title;

  /// 제목 아래 한 줄. **한 줄까지만** — 설명이 길어지면 확인 대화상자로 옮긴다(#445).
  final String? subtitle;
  final List<Widget> children;

  const SheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: T.bgTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: T.textFaint, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: T.textPrimary)),
                if (subtitle case final line?) ...[
                  const SizedBox(height: 4),
                  Text(line, style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
                ],
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 채움 버튼 — §5.5 Primary. 그라데이션 위의 흰 글자. 눌릴 수 없으면 옅은 회색이다.
///
/// 안쪽은 진짜 `FilledButton` 이라 테스트의 `find.widgetWithText(FilledButton, …)` 과
/// `tester.widget<FilledButton>(find.byKey(buttonKey))` 가 그대로 산다.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// 안쪽 `FilledButton` 에 붙는 키 — 테스트가 버튼을 찾는 손잡이다.
  final Key? buttonKey;

  /// 그라데이션. 기본은 [T.warm](홈 CTA 와 같은 것). 시그니처를 쓰려면 [T.sig].
  final LinearGradient gradient;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.gradient = T.warm,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? gradient : null,
        color: enabled ? null : T.textFaint.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? const [BoxShadow(color: T.warmGlow, blurRadius: 16, offset: Offset(0, 6))]
            : null,
      ),
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

/// 아웃라인 버튼 — §5.5 Secondary. 흰 반투명 배경, 옅은 테두리, 라벨은 [T.textSecondary].
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  /// 지우기·나가기처럼 되돌리기 어려운 것은 붉게 쓴다.
  final bool danger;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.danger = false,
  });

  static const Color dangerColor = Color(0xFFD2604F);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: T.cardBg,
        foregroundColor: danger ? dangerColor : T.textSecondary,
        disabledForegroundColor: T.textFaint,
        side: const BorderSide(color: T.cardBorder),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

/// 눌러서 고르는 값(날짜·시각·끝나는 날) 을 보여 주는 흰 상자. 아이콘 + 값.
class PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// 값을 비울 수 있으면 오른쪽에 × 가 붙는다(시각 없음 → "하루 종일").
  final VoidCallback? onClear;
  final String clearTooltip;

  const PickerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onClear,
    this.clearTooltip = '지우기',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: T.line),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: T.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: T.textPrimary)),
            ),
            if (onClear != null)
              Tooltip(
                message: clearTooltip,
                child: GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.close_rounded, size: 16, color: T.textMuted),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// 입력칸 — 흰 채움 + 옅은 테두리. 머티리얼 `OutlineInputBorder` 를 안 쓴다.
class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const GlassField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: T.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: T.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: T.textMuted),
          border: InputBorder.none,
          isDense: true,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

/// 알약 칩 — §5.6. 선택하면 강조색으로 채우고 흰 글자, 아니면 흰 반투명에 옅은 테두리.
class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// 가로로 꽉 채우는 칸(종·몸집처럼 셋을 나란히)이면 `true` — 가운데 정렬 상자가 된다.
  final bool stretch;

  /// 골랐을 때 채우는 색. 기본은 강조색이고, 사람 칩은 그 사람의 색을 준다(#736).
  final Color color;

  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.stretch = false,
    this.color = T.accent,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: stretch
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      alignment: stretch ? Alignment.center : null,
      decoration: BoxDecoration(
        // 안 골린 칩은 옅은 회색 면 — 흰 바탕에서 흰 칩은 안 보인다(#447).
        color: selected ? color : T.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? color : T.cardBorder),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : T.textSecondary)),
    );
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: chip);
  }
}

/// 칸 이름. 위계는 §3 의 "날짜/메타" 줄과 같다.
class FormLabel extends StatelessWidget {
  final String text;

  const FormLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
      );
}

/// 둥근 그라데이션 버튼 — 탭 바의 산책 버튼과 같은 모양(§5.4). 화면 머리말의 "새로 적기".
class SigFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  const SigFab({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: T.sig,
              boxShadow: [
                BoxShadow(color: T.sigGlow, blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.58),
          ),
        ),
      ),
    );
  }
}

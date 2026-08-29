import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 채팅방 — 기본은 '우리 가족'(물·밥·산책을 함께 챙기는 대화방).
/// 채팅 목록에서 방 이름/부제를 넘겨 재사용한다. 백엔드 연동 전 로컬 상태.
class FamilyChatScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<ChatMessage>? messages; // 방별 메시지(null이면 가족방 기본)
  const FamilyChatScreen({super.key, this.title = '우리 가족', this.subtitle = '', this.messages});

  @override
  State<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends State<FamilyChatScreen> {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  late final List<ChatMessage> _msgs = [...(widget.messages ?? kChatMessages)];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 발신자 이름 → 가족 구성원 색. 가족이 아니면 이름 해시로 팔레트 색 배정.
  Color _memberColor(String name) {
    for (final m in kFamilyMembers) {
      if (m.name == name) return m.color;
    }
    const palette = [
      Color(0xFF33BFA6), Color(0xFF5B8DEF), Color(0xFF9B7BFF),
      Color(0xFFEFA13C), Color(0xFFFF7E8A), Color(0xFF57C98A),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final hh = '${now.hour}'.padLeft(2, '0');
    final mm = '${now.minute}'.padLeft(2, '0');
    setState(() => _msgs.add(ChatMessage('나', text, '$hh:$mm', mine: true)));
    _ctrl.clear();
    // 프레임 반영 후 맨 아래로 스크롤.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            _header(context),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubbleRow(context, _msgs[i]),
              ),
            ),
            _inputBar(context),
          ]),
        ),
      ),
    );
  }

  // ───────────── 헤더 ─────────────
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xB3FFFFFF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0x80FFFFFF)),
            ),
            child: const Icon(Icons.arrow_back, size: 22, color: T.textPrimary),
          ),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 2),
          Text(widget.subtitle.isEmpty ? '${kFamilyMembers.length}명' : widget.subtitle,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: T.textMuted)),
        ]),
      ]),
    );
  }

  // ───────────── 말풍선 ─────────────
  Widget _bubbleRow(BuildContext context, ChatMessage m) {
    final maxW = MediaQuery.of(context).size.width * 0.68;
    if (m.mine) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: _warm,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7E8A).withValues(alpha: 0.24),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(m.text,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 4),
          Text(m.time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
        ]),
      );
    }

    const br = BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(16),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(m.sender),
        const SizedBox(width: 9),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.sender,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: ClipRRect(
                borderRadius: br,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xD6FFFFFF),
                      borderRadius: br,
                      border: Border.all(color: const Color(0xCCFFFFFF)),
                    ),
                    child: Text(m.text,
                        style: const TextStyle(fontSize: 13.5, height: 1.45, color: T.textPrimary)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(m.time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
          ]),
        ),
      ]),
    );
  }

  // 발신자 원형 아바타 (이름 첫 글자).
  Widget _avatar(String name) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _memberColor(name)),
      child: Text(
        name.characters.first,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }

  // ───────────── 입력바 ─────────────
  Widget _inputBar(BuildContext context) {
    // 키보드가 올라오면 Scaffold(resizeToAvoidBottomInset 기본값)가 몸체를 밀어올리므로,
    // 여기서는 키보드 유무에 따라 하단 세이프에어리어 패딩만 조절한다.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, keyboardOpen ? 10 : safeBottom + 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x14785AA0))),
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFF8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 14, color: T.textPrimary),
              decoration: const InputDecoration(
                hintText: '메시지 보내기...',
                hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _warm,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF7E8A).withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_upward, size: 22, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

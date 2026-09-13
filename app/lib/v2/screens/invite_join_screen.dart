import 'package:flutter/material.dart';

import '../data/chat_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 초대코드로 방에 들어가는 화면. (이슈 #81 완료 조건 4)
///
/// **실패 네 가지를 각각 다르게 말한다.** 하나로 뭉치면 사용자는 자기가 할 일을 모른다.
///
/// | 서버 | 사용자가 할 일 |
/// |---|---|
/// | `INVITE_EXPIRED` (410) | 새 코드를 받는다 |
/// | `INVITE_REVOKED` (410) | 방장에게 새 코드를 받는다 |
/// | `INVITE_USES_EXHAUSTED` (409) | 새 코드를 받는다 |
/// | `ROOM_MEMBER_LIMIT` (409) | **자리가 나기를 기다린다** — 코드를 다시 받아도 소용없다 |
///
/// 마지막 하나가 나머지 셋과 다르다. "새 코드를 받으세요" 라고 말하면 사용자는 코드를 다시
/// 받아 와서 또 실패한다.
class InviteJoinScreen extends StatefulWidget {
  const InviteJoinScreen({super.key, ChatRepository? repository}) : _injected = repository;

  final ChatRepository? _injected;

  @override
  State<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends State<InviteJoinScreen> {
  late final ChatRepository _repo = widget._injected ?? ChatRepository();
  final TextEditingController _code = TextEditingController();

  bool _sending = false;
  ChatFailure? _failure;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await _repo.joinByInviteCode(code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ChatFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: T.textPrimary,
        title: const Text('초대코드로 참여',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: AuroraBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text('방장에게 받은 코드를 입력해 주세요',
                  style: TextStyle(fontSize: 13.5, color: T.textSecondary)),
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _join(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '초대코드',
                    hintStyle: TextStyle(color: T.textMuted),
                  ),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 14),
                _failureCard(_failure!),
              ],
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _sending ? null : _join,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [T.sigStart, T.sigEnd]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('참여하기',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failureCard(ChatFailure failure) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_iconFor(failure.kind), size: 18, color: const Color(0xFFE2725B)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(failure.message,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
            if (_hint(failure.kind) case final hint?) ...[
              const SizedBox(height: 4),
              Text(hint, style: const TextStyle(fontSize: 12, color: T.textSecondary)),
            ],
          ]),
        ),
      ]),
    );
  }

  static IconData _iconFor(ChatFailureKind kind) => switch (kind) {
        ChatFailureKind.roomFull => Icons.groups_rounded,
        ChatFailureKind.inviteExpired ||
        ChatFailureKind.inviteRevoked ||
        ChatFailureKind.inviteExhausted =>
          Icons.key_off_rounded,
        _ => Icons.error_outline_rounded,
      };

  /// 사용자가 **다음에 할 일**. 문구가 넷 다 달라야 하는 이유가 여기 있다.
  static String? _hint(ChatFailureKind kind) => switch (kind) {
        ChatFailureKind.roomFull => '코드를 다시 받아도 들어올 수 없어요. 자리가 나면 다시 시도해 주세요.',
        ChatFailureKind.inviteExpired ||
        ChatFailureKind.inviteRevoked ||
        ChatFailureKind.inviteExhausted =>
          '방장에게 새 코드를 요청해 주세요.',
        ChatFailureKind.notFound => '코드를 다시 확인해 주세요.',
        _ => null,
      };
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/chat_outbox.dart';
import '../data/chat_polling_policy.dart';
import '../data/chat_repository.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 채팅방 하나. **서버에 붙어 있다.** (이슈 #81)
///
/// ## 폴링
///
/// 간격은 [ChatPollingPolicy] 가 정한다 — 이 화면은 타이머만 굴린다. 정책을 순수 함수로
/// 떼어 둔 덕에 "3초인가 30초인가" 는 시간을 기다리지 않고 테스트한다.
///
/// 델타로 받는다 — 마지막으로 받은 `roomSeq` 를 `afterSeq` 로 보내고, 서버가 준 `ETag` 를
/// `If-None-Match` 로 되돌려 보낸다. 새 것이 없으면 **304** 라 본문이 아예 안 온다.
///
/// ## 낙관적 전송
///
/// 보낸 즉시 회색으로 넣는다. 성공하면 서버가 준 메시지로 바뀌고, **실패해도 지우지 않는다** —
/// 재전송 버튼이 붙는다. 재전송은 [PendingMessage.retrying] 이라 **같은 멱등키**를 다시 쓴다.
/// 새로 만들면 서버에 같은 말이 두 번 남는다.
///
/// ## 읽음
///
/// 방을 열 때와 새 메시지를 받을 때 `POST /rooms/{id}/read` 를 보낸다. 미읽음 뱃지는 서버가
/// 계산하므로 앱이 0으로 지레짐작하지 않는다.
class FamilyChatScreen extends StatefulWidget {
  final int roomId;
  final String title;
  final String subtitle;

  const FamilyChatScreen({
    super.key,
    required this.roomId,
    this.title = '우리 가족',
    this.subtitle = '',
    ChatRepository? repository,
  }) : _injected = repository;

  final ChatRepository? _injected;

  @override
  State<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends State<FamilyChatScreen> with WidgetsBindingObserver {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  late final ChatRepository _repo = widget._injected ?? ChatRepository();
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<ChatMessageItem> _messages = [];
  final List<PendingMessage> _pending = [];

  Timer? _timer;
  int _lastSeq = 0;
  String? _etag;
  int _consecutiveEmptyPolls = 0;
  bool _inForeground = true;
  bool _loading = true;
  ChatFailure? _failure;

  int? get _myUserId => AuthState.user?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll(initial: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _inForeground) {
      return;
    }
    _inForeground = foreground;
    _timer?.cancel();
    if (foreground) {
      // 돌아온 순간 낡은 화면이 가장 눈에 띈다. 정책이 Duration.zero 를 준다.
      _scheduleNext(justResumed: true);
    } else {
      _scheduleNext();
    }
  }

  void _scheduleNext({bool justResumed = false}) {
    _timer?.cancel();
    final delay = ChatPollingPolicy.nextInterval(
      inForeground: _inForeground,
      consecutiveEmptyPolls: _consecutiveEmptyPolls,
      justResumed: justResumed,
    );
    _timer = Timer(delay, _poll);
  }

  Future<void> _poll({bool initial = false}) async {
    try {
      final page = await _repo.messages(
        widget.roomId,
        afterSeq: _lastSeq == 0 ? null : _lastSeq,
        etag: _etag,
      );
      if (!mounted) return;

      final fresh = page.messages.where((m) => m.roomSeq > _lastSeq).toList();
      setState(() {
        _loading = false;
        _failure = null;
        _etag = page.etag;
        if (fresh.isNotEmpty) {
          _messages.addAll(fresh);
          _messages.sort((a, b) => a.roomSeq.compareTo(b.roomSeq));
          _lastSeq = _messages.last.roomSeq;
          // 새 것이 왔으면 간격을 되돌린다 — 대화가 다시 시작된 순간 느리면 안 된다.
          _consecutiveEmptyPolls = 0;
          _dropConfirmedPending();
        } else {
          _consecutiveEmptyPolls++;
        }
      });

      if (fresh.isNotEmpty || initial) {
        _reportRead();
        _scrollToBottom();
      }
    } on ChatFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 폴링 실패는 화면을 비우지 않는다 — 이미 받은 메시지는 그대로 둔다.
        _failure = _messages.isEmpty ? e : null;
        _consecutiveEmptyPolls++;
      });
    } finally {
      if (mounted) {
        _scheduleNext();
      }
    }
  }

  /// 서버가 확정한 메시지가 도착하면 그 대기 항목을 목록에서 뺀다.
  ///
  /// 본문으로 맞춘다. `clientMsgId` 를 서버가 돌려주지 않기 때문이다 — 같은 본문을 연속으로
  /// 두 번 보낸 경우 한 번에 하나씩만 빠지므로, 두 번째 응답이 오면 나머지도 빠진다.
  void _dropConfirmedPending() {
    for (final message in _messages) {
      if (message.senderUserId != _myUserId) {
        continue;
      }
      final index = _pending.indexWhere(
        (p) => p.body == message.body && p.state == PendingState.sending,
      );
      if (index >= 0) {
        _pending.removeAt(index);
      }
    }
  }

  Future<void> _reportRead() async {
    if (_lastSeq == 0) {
      return;
    }
    try {
      await _repo.markRead(widget.roomId, _lastSeq);
    } on ChatFailure {
      // 읽음 보고 실패는 사용자에게 알리지 않는다. 다음 폴링이 다시 보낸다.
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      return;
    }
    _ctrl.clear();
    final message = PendingMessage.create(text);
    setState(() => _pending.add(message));
    _scrollToBottom();
    await _deliver(message);
  }

  /// 실제 전송. [PendingMessage.retrying] 이 준 것도 여기로 온다 — **같은 멱등키**다.
  Future<void> _deliver(PendingMessage message) async {
    try {
      final sent = await _repo.send(widget.roomId, message.body, message.clientMsgId);
      if (!mounted) return;
      setState(() {
        _pending.remove(message);
        if (sent.roomSeq > _lastSeq) {
          _messages.add(sent);
          _lastSeq = sent.roomSeq;
        }
        _consecutiveEmptyPolls = 0;
      });
      _scrollToBottom();
    } on ChatFailure {
      if (!mounted) return;
      // **지우지 않는다.** 사용자가 쓴 글이 사라지면 안 되고, 그냥 두면 보낸 것처럼 보인다.
      setState(() {
        final index = _pending.indexOf(message);
        if (index >= 0) {
          _pending[index] = message.failed();
        }
      });
    }
  }

  Future<void> _retry(PendingMessage message) async {
    final retrying = message.retrying();
    setState(() {
      final index = _pending.indexOf(message);
      if (index >= 0) {
        _pending[index] = retrying;
      }
    });
    await _deliver(retrying);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  /// 발신자 이름 → 색. 가족 구성원이면 그 색, 아니면 이름 해시로 팔레트에서 고른다.
  Color _memberColor(String name) {
    for (final m in kFamilyMembers) {
      if (m.name == name) return m.color;
    }
    const palette = [
      Color(0xFF33BFA6),
      Color(0xFF5B8DEF),
      Color(0xFF9B7BFF),
      Color(0xFFEFA13C),
      Color(0xFFFF7E8A),
      Color(0xFF57C98A),
    ];
    return palette[name.hashCode.abs() % palette.length];
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
            Expanded(child: _list(context)),
            _inputBar(context),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_failure!.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: T.textSecondary)),
        ),
      );
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return const Center(
        child: Text('아직 대화가 없어요. 먼저 인사해 보세요 🐾',
            style: TextStyle(fontSize: 13.5, color: T.textMuted)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      itemCount: _messages.length + _pending.length,
      itemBuilder: (_, i) => i < _messages.length
          ? _bubbleRow(context, _messages[i])
          : _pendingRow(context, _pending[i - _messages.length]),
    );
  }

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
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: T.textPrimary)),
          const SizedBox(height: 2),
          Text(widget.subtitle,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: T.textMuted)),
        ]),
      ]),
    );
  }

  /// 아직 서버가 확정하지 않은 말풍선. 회색이고, 실패하면 재전송 버튼이 붙는다.
  Widget _pendingRow(BuildContext context, PendingMessage message) {
    final maxW = MediaQuery.of(context).size.width * 0.68;
    final failed = message.state == PendingState.failed;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFB9AECB),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(message.body,
                style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 4),
        if (failed)
          GestureDetector(
            onTap: () => _retry(message),
            behavior: HitTestBehavior.opaque,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFE2725B)),
              SizedBox(width: 4),
              Text('보내지 못했어요 · 다시 보내기',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE2725B))),
            ]),
          )
        else
          const Text('보내는 중…', style: TextStyle(fontSize: 11, color: T.textMuted)),
      ]),
    );
  }

  Widget _bubbleRow(BuildContext context, ChatMessageItem m) {
    final maxW = MediaQuery.of(context).size.width * 0.68;
    final mine = _myUserId != null && m.senderUserId == _myUserId;
    final time = _hhmm(m.createdAt);

    if (mine) {
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
              child: Text(_bodyOf(m),
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 4),
          Text(time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
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
        _avatar(m.senderName),
        const SizedBox(width: 9),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.senderName,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
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
                    child: Text(_bodyOf(m),
                        style: const TextStyle(
                            fontSize: 13.5, height: 1.45, color: T.textPrimary)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
          ]),
        ),
      ]),
    );
  }

  /// 삭제된 메시지도 **자리를 지운다**. 목록에서 빼면 그 `roomSeq` 가 도달하지 않아
  /// 읽음 커서가 그 번호를 넘지 못하고 미읽음 뱃지가 영원히 남는다 (ADR-0011).
  static String _bodyOf(ChatMessageItem m) => m.deleted ? '삭제된 메시지예요' : m.body;

  static String _hhmm(DateTime? at) {
    if (at == null) {
      return '';
    }
    final local = at.toLocal();
    final hh = '${local.hour}'.padLeft(2, '0');
    final mm = '${local.minute}'.padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _avatar(String name) {
    final color = _memberColor(name);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _inputBar(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 14),
      child: Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x80FFFFFF)),
            ),
            child: TextField(
              controller: _ctrl,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '메시지 보내기',
                hintStyle: TextStyle(color: T.textMuted),
              ),
              style: const TextStyle(fontSize: 14, color: T.textPrimary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(gradient: _warm, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/chat_outbox.dart';
import '../data/chat_polling_policy.dart';
import '../data/chat_repository.dart';
import '../data/chat_terms_gate.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/chat_terms_dialog.dart';
import '../widgets/message_actions_sheet.dart';

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

  /// 내가 이 방의 방장인가. **강퇴 버튼을 띄울지의 유일한 근거다.**
  ///
  /// 방 목록이 이미 `myRole` 을 들고 있어서 그것을 넘겨받는다 — 이 화면이 다시 물으면
  /// 방을 열 때마다 쿼리가 하나 는다. 모르면 `false` 다: <b>못 하는 버튼을 보여 주고 403 을
  /// 받게 하느니 감춘다.</b>
  final bool isOwner;

  const FamilyChatScreen({
    super.key,
    required this.roomId,
    this.title = '우리 가족',
    this.subtitle = '',
    this.isOwner = false,
    ChatRepository? repository,
    ChatTermsGate? termsGate,
  })  : _injected = repository,
        _injectedGate = termsGate;

  final ChatRepository? _injected;
  final ChatTermsGate? _injectedGate;

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
  late final ChatTermsGate _terms = widget._injectedGate ?? const ChatTermsGate();
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

  /// "보기" 를 눌러 펼쳐 둔 메시지들의 `roomSeq`.
  ///
  /// **서버에 안 남긴다.** 가려 둔 것을 영구히 푸는 것은 가리기 해제이고, 이건 한 번 들여다
  /// 보는 것이다. 화면을 나가면 다시 접힌다 — 그게 사용자가 기대하는 동작이다.
  final Set<int> _revealed = {};

  int? get _myUserId => AuthState.user?.id;

  /// 동의를 아직 안 받았다. 이 동안에는 **폴링도 안 한다** — 동의 전에 대화를 받아
  /// 두면 창을 닫는 순간 남의 말이 화면에 그려진다.
  bool _awaitingTerms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAfterTerms();
  }

  /// 채팅 첫 진입에 약관 동의를 받는다 — Google Play UGC 정책(#82 완료 조건 6).
  ///
  /// 동의하지 않으면 **방을 열지 않고 되돌아간다.** 강제로 동의시키면 그건 동의가 아니라
  /// 통보다. 로그인 전이면 묻지 않는다 — 누구의 동의인지 정할 수 없고, 어차피 서버가 401 이다.
  Future<void> _startAfterTerms() async {
    final userId = _myUserId;
    if (userId == null || await _terms.hasAgreed(userId)) {
      await _poll(initial: true);
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _awaitingTerms = true;
      _loading = false;
    });

    final agreed = await ChatTermsDialog.show(context);
    if (!mounted) {
      return;
    }
    if (!agreed) {
      Navigator.of(context).maybePop();
      return;
    }

    await _terms.markAgreed(userId);
    if (!mounted) {
      return;
    }
    setState(() {
      _awaitingTerms = false;
      _loading = true;
    });
    await _poll(initial: true);
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
    if (_awaitingTerms) {
      // 동의 전에는 폴링하지 않는다. 받아 두면 창을 닫는 순간 남의 말이 화면에 그려진다.
      return;
    }
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
      // 시스템 이모지(🐾)는 기기마다 다르게 그려진다 — 앱의 이모지 자산으로(#330).
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/emoji/paw.png', width: 40, height: 40),
          const SizedBox(height: 10),
          const Text('아직 대화가 없어요. 먼저 인사해 보세요',
              style: TextStyle(fontSize: 13.5, color: T.textMuted)),
        ]),
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
              child: GestureDetector(
                // 길게 눌러 신고·가리기. 탭이 아니라 롱프레스인 것은 스크롤 중에 실수로
                // 열리면 안 되기 때문이다 — 카카오·라인·왓츠앱이 모두 같은 제스처다.
                onLongPress: () => _openMessageActions(m),
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
                    child: _otherBody(m),
                  ),
                ),
              ),
              ),
            ),
            if (_isFolded(m))
              TextButton(
                onPressed: () => setState(() => _revealed.add(m.roomSeq)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('보기',
                    style: TextStyle(fontSize: 12, color: T.textSecondary)),
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
  /// 말풍선에 실제로 그릴 글.
  ///
  /// **삭제가 가리기보다 앞선다.** 지워진 말은 가렸든 안 가렸든 없는 말이다.
  String _bodyOf(ChatMessageItem m) {
    if (m.deleted) {
      return '삭제된 메시지예요';
    }
    if (m.hiddenByBlock && !_revealed.contains(m.roomSeq)) {
      return '가린 사람의 메시지입니다.';
    }
    return m.body;
  }

  /// 메시지를 길게 눌렀을 때. 신고 · 가리기 · (방장이면) 내보내기.
  ///
  /// **내 메시지에는 안 뜬다** — 자기 메시지는 신고도 가리기도 뜻이 없다.
  Future<void> _openMessageActions(ChatMessageItem m) async {
    final mine = _myUserId != null && m.senderUserId == _myUserId;
    if (mine && m.deleted) {
      return; // 이미 지운 자리 — 할 수 있는 것이 없다.
    }

    final action = await MessageActionsSheet.show(
      context,
      senderName: mine ? '내 메시지' : m.senderName,
      hiddenByBlock: m.hiddenByBlock,
      canRemoveMember: widget.isOwner,
      isMine: mine,
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case MessageAction.report:
        await _report(m);
      case MessageAction.block:
        await _block(m.senderUserId, m.senderName);
      case MessageAction.unblock:
        await _unblock(m.senderUserId, m.senderName);
      case MessageAction.removeMember:
        await _removeMember(m.senderUserId, m.senderName);
      case MessageAction.delete:
        await _deleteMine(m);
    }
  }

  /// 내 메시지를 지운다 — 이슈 #197.
  ///
  /// 서버가 204 를 주면 목록의 그 자리를 **지운 모양으로 바꾼다.** 델타 폴링은 새 번호만
  /// 가져오므로 옛 번호의 변화는 스스로 반영해야 한다 — 안 그러면 다음에 방을 다시 열 때까지
  /// 지운 말이 그대로 보인다.
  Future<void> _deleteMine(ChatMessageItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이 메시지를 삭제할까요?'),
        content: const Text(
          '상대방 화면에서도 내용이 사라지고 "삭제된 메시지" 자리만 남아요.'
          '\n되돌릴 수 없어요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제', style: TextStyle(color: Color(0xFFD64545))),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) {
      return;
    }
    try {
      await _repo.deleteMessage(m.id);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((x) => x.roomSeq == m.roomSeq);
        if (i >= 0) {
          _messages[i] = ChatMessageItem(
            id: m.id,
            roomSeq: m.roomSeq,
            senderUserId: m.senderUserId,
            senderName: m.senderName,
            body: '',
            createdAt: m.createdAt,
            deleted: true,
            hiddenByBlock: m.hiddenByBlock,
          );
        }
      });
      _toast('메시지를 삭제했어요');
    } on ChatFailure catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _report(ChatMessageItem m) async {
    final choice = await ReportSheet.show(
      context,
      senderName: m.senderName,
      subject: '메시지 1개',
    );
    if (!mounted || choice == null) {
      return;
    }

    try {
      await _repo.report(widget.roomId, [m.roomSeq], choice.reason, memo: choice.memo);
      // 신고가 성공한 뒤에만 가린다. 순서가 반대면 신고가 실패했을 때 "가려졌는데 접수는
      // 안 된" 상태가 되고, 사용자는 접수됐다고 믿는다.
      if (choice.alsoBlock) {
        await _repo.block(m.senderUserId);
        await _refreshAfterBlockChange();
      }
      _toast('신고를 접수했어요. 상대에게는 알리지 않습니다');
    } on ChatFailure catch (e) {
      _toast(e.message);
    }
  }

  /// 방에서 내보낸다. **되돌리기 어려운 동작이라 확인을 받는다.**
  ///
  /// 문구가 재입장 금지와 푸는 방법을 함께 말한다 — 이슈 #82 가 정한 그대로다. 라인이
  /// 재입장 금지를 12.9.0 에서 나중에 따로 붙인 것은 실제로 생기는 문제라는 뜻이다.
  Future<void> _removeMember(int userId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$name 님을 내보냅니다'),
        content: const Text(
          '초대코드를 다시 받아도 들어올 수 없습니다.'
          '\n방 설정에서 다시 풀 수 있습니다.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('내보내기', style: TextStyle(color: Color(0xFFD64545))),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) {
      return;
    }

    try {
      await _repo.removeMember(widget.roomId, userId);
      // 그 사람이 쓴 메시지는 방에 남는다 — 지우면 신고 근거가 사라진다. 그래서 목록을
      // 다시 받지 않는다. 바뀐 것은 멤버십이지 대화가 아니다.
      _toast('$name 님을 내보냈어요');
    } on ChatFailure catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _block(int userId, String name) async {
    try {
      await _repo.block(userId);
      await _refreshAfterBlockChange();
      _toast('$name 님의 메시지를 가렸어요');
    } on ChatFailure catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _unblock(int userId, String name) async {
    try {
      await _repo.unblock(userId);
      await _refreshAfterBlockChange();
      _toast('$name 님의 메시지를 다시 보여 줄게요');
    } on ChatFailure catch (e) {
      _toast(e.message);
    }
  }

  /// 가리기가 바뀌면 **이미 받아 둔 메시지의 표시가 낡는다.**
  ///
  /// `hiddenByBlock` 은 서버가 읽는 사람 기준으로 계산해서 붙이는 값이라, 델타 폴링으로는
  /// 새 메시지만 바뀌고 과거 메시지는 옛 값 그대로다. 그래서 처음부터 다시 받는다 —
  /// 가리기는 자주 하는 일이 아니라 이 비용이 문제되지 않는다.
  Future<void> _refreshAfterBlockChange() async {
    _messages.clear();
    _revealed.clear();
    _lastSeq = 0;
    _etag = null;
    await _poll(initial: true);
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 남의 말풍선 본문. 접혀 있으면 흐린 기울임으로 그린다.
  ///
  /// **본문을 지워서 그리지 않는다.** 서버가 본문을 그대로 내려보내고("보기" 를 누를 때
  /// 요청이 한 번 더 필요하지 않도록) 접는 것은 여기다.
  Widget _otherBody(ChatMessageItem m) {
    final folded = _isFolded(m);
    return Text(
      _bodyOf(m),
      style: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: folded ? T.textMuted : T.textPrimary,
        fontStyle: folded ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }

  /// 이 말풍선이 지금 접혀 있는가.
  bool _isFolded(ChatMessageItem m) =>
      m.hiddenByBlock && !m.deleted && !_revealed.contains(m.roomSeq);

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

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/chat_outbox.dart';
import '../domain/chat_thread.dart';
import '../data/chat_polling_policy.dart';
import '../data/chat_repository.dart';
import '../data/chat_terms_gate.dart';
import '../data/image_prep.dart';
import '../data/media_picker.dart';
import '../data/post_media_repository.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/chat_terms_dialog.dart';
import '../widgets/message_actions_sheet.dart';
import '../widgets/post_media_viewer.dart';

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
///
/// ## 읽기 흐름 (#452)
///
/// 말풍선은 [layoutThread] 가 묶는다 — 같은 사람의 같은 분(minute)은 한 묶음(이름은 첫 말,
/// 시각은 마지막 말), 날이 바뀌면 날짜 구분선. 위로 올려 옛 말을 읽는 중에 새 말이 오면
/// **끌어내리지 않는다** — 아래에 "새 메시지 N개" 알약을 띄우고, 누르거나 바닥에 닿으면 사라진다
/// (카카오톡 · Instagram DM). 내가 보낸 말은 언제나 바닥으로 간다.
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
    this.picker,
    this.media,
    this.prepare = ImagePrep.prepare,
  })  : _injected = repository,
        _injectedGate = termsGate;

  final ChatRepository? _injected;
  final ChatTermsGate? _injectedGate;

  /// 사진 보내기(#452)의 세 부품 — 고르기 · 다시 인코딩 · 올리기. 위젯 테스트가 가짜를 꽂는다.
  final MediaPicker? picker;
  final PostMediaRepository? media;
  final ImagePreparer prepare;

  @override
  State<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends State<FamilyChatScreen> with WidgetsBindingObserver {
  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [T.warmStart, T.warmEnd],
  );

  late final ChatRepository _repo = widget._injected ?? ChatRepository();
  late final ChatTermsGate _terms = widget._injectedGate ?? const ChatTermsGate();
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 바닥 근처인가 — 이 안이면 새 말이 올 때 따라 내려간다.
  bool _nearBottom = true;

  /// 위에서 읽는 동안 온 남의 말 개수 — "새 메시지 N개" 알약.
  int _unseen = 0;

  /// 바닥에서 이만큼 안이면 "바닥 근처". 말풍선 한둘 높이다.
  static const double _nearBottomPx = 160;

  final List<ChatMessageItem> _messages = [];
  final List<PendingMessage> _pending = [];
  late final PostMediaRepository _media = widget.media ?? PostMediaRepository();
  late final MediaPicker _picker = widget.picker ?? ImagePickerMediaPicker();
  bool _picking = false;

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
    _scroll.addListener(_onScroll);
    _startAfterTerms();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final near = _scroll.position.maxScrollExtent - _scroll.offset < _nearBottomPx;
    if (near == _nearBottom && !(near && _unseen > 0)) return;
    setState(() {
      _nearBottom = near;
      // 바닥에 닿으면 새 말은 본 것이다.
      if (near) _unseen = 0;
    });
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
    _scroll.removeListener(_onScroll);
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
        final me = _myUserId;
        final others = fresh.where((m) => m.senderUserId != me).length;
        if (initial || _nearBottom || others == 0) {
          _scrollToBottom();
        } else {
          // 위에서 옛 말을 읽는 중이다 — 끌어내리지 말고 알약으로 알린다.
          setState(() => _unseen += others);
        }
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
      // 사진 메시지(#452)는 올린 사진 id 로, 글자는 본문으로 맞춘다.
      final index = _pending.indexWhere(
        (p) => p.state == PendingState.sending &&
            (p.mediaId != null ? message.media?.id == p.mediaId : !p.isPhoto && p.body == message.body),
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

  /// 사진 보내기(#452) — 고른 만큼 메시지가 된다(**사진 하나에 메시지 하나**, 카카오톡과 같다).
  /// 열 장까지. 글 사진과 같은 길이다: 다시 인코딩(위치 정보 제거 · 긴 변 1600) → `POST /media`
  /// (CHAT_IMAGE) → 전송. 한 장씩 차례로 보내 순서가 고른 순서다.
  Future<void> _pickPhotos() async {
    if (_picking) return;
    _picking = true;
    try {
      final picked = await _picker.pickImages(limit: 10);
      if (!mounted || picked.isEmpty) return;
      for (final image in picked) {
        final PendingPhoto photo;
        try {
          final prepared = await widget.prepare(image.bytes);
          photo = PendingPhoto(bytes: prepared.bytes, width: prepared.width, height: prepared.height);
        } on ImagePrepException {
          if (mounted) _toast('이 사진은 읽을 수 없어요');
          continue;
        }
        if (!mounted) return;
        final message = PendingMessage.photo(photo);
        setState(() => _pending.add(message));
        _scrollToBottom();
        await _deliver(message);
        if (!mounted) return;
      }
    } finally {
      _picking = false;
    }
  }

  /// 실제 전송. [PendingMessage.retrying] 이 준 것도 여기로 온다 — **같은 멱등키**다.
  ///
  /// 사진이면 **먼저 올린다**(#452). 올린 id 는 대기 항목에 적어 두므로 전송만 실패한 재시도는
  /// 다시 올리지 않는다 — 같은 사진이 버킷에 두 번 남지 않는다.
  Future<void> _deliver(PendingMessage message) async {
    var current = message;
    try {
      final photo = current.photo;
      if (photo != null && current.mediaId == null) {
        final uploaded = await _media.upload(
          jpegBytes: photo.bytes,
          width: photo.width,
          height: photo.height,
          filename: 'chat.jpg',
          category: PostMediaRepository.chatCategory,
        );
        current = current.uploaded(uploaded.id);
        if (!mounted) return;
        setState(() => _replacePending(current));
      }
      final sent = await _repo.send(widget.roomId, current.body, current.clientMsgId, mediaId: current.mediaId);
      if (!mounted) return;
      setState(() {
        _pending.removeWhere((p) => p.clientMsgId == current.clientMsgId);
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
      setState(() => _replacePending(current.failed()));
    } on PostMediaFailure catch (e) {
      if (!mounted) return;
      // 사진을 못 올렸다 — 같은 자리에 남기고 다시 보내기. 거절(너무 큼 등)이면 이유를 말한다.
      setState(() => _replacePending(current.failed()));
      if (e.kind == PostMediaFailureKind.rejected) _toast(e.label);
    }
  }

  /// 같은 멱등키의 대기 항목을 바꿔 끼운다 — 올린 id 가 붙거나 상태가 바뀔 때.
  void _replacePending(PendingMessage next) {
    final index = _pending.indexWhere((p) => p.clientMsgId == next.clientMsgId);
    if (index >= 0) {
      _pending[index] = next;
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
    if (_unseen != 0) setState(() => _unseen = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _settleToBottom(3));
  }

  /// 바닥까지 — 지연 생성 목록은 아직 안 만든 줄의 높이를 어림하므로, 내려가 보니 더 남았으면
  /// 한 번 더 간다(최대 [tries] 번). 안 그러면 새 말 두어 개 위에서 멈춘다.
  Future<void> _settleToBottom(int tries) async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    if (!mounted || !_scroll.hasClients || tries <= 1) return;
    if (_scroll.position.maxScrollExtent - _scroll.offset > 1) {
      await _settleToBottom(tries - 1);
    }
  }

  /// "새 메시지 N개" 알약 — 위에서 읽는 동안 남의 말이 왔을 때만. 누르면 바닥으로.
  Widget _newMessagesPill() => Positioned(
        left: 0,
        right: 0,
        bottom: 10,
        child: Center(
          child: GestureDetector(
            key: const Key('chat-new-messages'),
            onTap: _scrollToBottom,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
              decoration: BoxDecoration(
                color: T.accent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: T.accent.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('새 메시지 $_unseen개',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_downward_rounded, size: 15, color: Colors.white),
              ]),
            ),
          ),
        ),
      );

  /// 날짜 구분선 — "2026년 9월 14일 월요일", 가운데 회색 알약(카카오톡).
  Widget _dayChip(String label) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Center(
          child: Container(
            key: const Key('chat-day-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ),
        ),
      );

  /// 발신자 이름 → 색. 가족 구성원이면 그 색, 아니면 이름 해시로 팔레트에서 고른다.
  Color _memberColor(String name) {
    for (final m in kFamilyMembers) {
      if (m.name == name) return m.color;
    }
    const palette = [
      Color(0xFF33BFA6),
      Color(0xFF5B8DEF),
      T.accent,
      Color(0xFFEFA13C),
      T.warmEnd,
      Color(0xFF57C98A),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
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
    // 묶음 · 날짜 구분선은 순수 함수가 정한다(#452, `chat_thread.dart`). 보내는 중인 말은 내 말이다.
    final me = 'u${_myUserId ?? 0}';
    final slots = layoutThread([
      for (final m in _messages) ThreadEntry(senderKey: 'u${m.senderUserId}', at: m.createdAt),
      for (final p in _pending) ThreadEntry(senderKey: me, at: p.createdAt),
    ], now: DateTime.now());
    final list = ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      itemCount: _messages.length + _pending.length,
      itemBuilder: (_, i) {
        final slot = slots[i];
        final row = i < _messages.length
            ? _bubbleRow(context, _messages[i], slot)
            : _pendingRow(context, _pending[i - _messages.length], slot);
        final day = slot.dayLabel;
        if (day == null) return row;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_dayChip(day), row]);
      },
    );
    return Stack(children: [
      list,
      if (_unseen > 0 && !_nearBottom) _newMessagesPill(),
    ]);
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
              color: T.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: T.cardBorder),
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
  Widget _pendingRow(BuildContext context, PendingMessage message, ThreadSlot slot) {
    final maxW = MediaQuery.of(context).size.width * 0.68;
    final failed = message.state == PendingState.failed;
    return Padding(
      padding: EdgeInsets.only(top: _gapAbove(slot)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: message.photo != null ? _pendingPhoto(message, maxW) : Container(
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

  /// 사진 말풍선의 폭 — 말풍선 최대 폭(화면의 68%)의 0.85. 카카오톡(말풍선 폭의 2/3)보다 조금 크고
  /// 인스타그램 DM(사진이 주인공)보다 작다 — 사진은 보이되 대화가 사진에 묻히지 않게.
  static const double _photoWidthFactor = 0.85;

  /// 보내는 중인 사진 — 확정되면 같은 자리에 서버 사진이 온다. 흐리게 두어 "아직" 임을 말한다.
  Widget _pendingPhoto(PendingMessage message, double maxW) {
    final photo = message.photo!;
    return Opacity(
      opacity: 0.6,
      child: ClipRRect(
        key: Key('chat-photo-pending-${message.clientMsgId}'),
        borderRadius: _photoRadius(mine: true),
        child: SizedBox(
          width: maxW * _photoWidthFactor,
          child: AspectRatio(
            aspectRatio: photo.aspectRatio,
            child: Image.memory(photo.bytes,
                fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => _photoFallback()),
          ),
        ),
      ),
    );
  }

  /// 사진 메시지의 줄(#452) — 사진이 말풍선이다. 캡션이 있으면 그 아래 작은 말풍선.
  Widget _photoRow(BuildContext context, ChatMessageItem m, ThreadSlot slot,
      {required double maxW, required bool mine, required String time}) {
    final tile = _photoTile(m, maxW, mine: mine);
    final caption = m.body.isEmpty ? null : _captionBubble(m, maxW, mine: mine);
    final timeText = Text(time, style: const TextStyle(fontSize: 11, color: T.textMuted));
    if (mine) {
      return Padding(
        padding: EdgeInsets.only(top: _gapAbove(slot)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          tile,
          if (caption != null) ...[const SizedBox(height: 4), caption],
          if (slot.showTime) ...[const SizedBox(height: 4), timeText],
        ]),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: _gapAbove(slot)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatarSlot(m.senderName, slot),
        const SizedBox(width: 9),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (slot.showHeader) ...[_senderName(m.senderName), const SizedBox(height: 4)],
            tile,
            if (caption != null) ...[const SizedBox(height: 4), caption],
            if (slot.showTime) ...[const SizedBox(height: 4), timeText],
          ]),
        ),
      ]),
    );
  }

  /// 묶음 안은 촘촘하게(3), 묶음 사이는 넓게(12) — iMessage · 카카오톡의 간격.
  static double _gapAbove(ThreadSlot slot) => slot.tight ? 3 : 12;

  /// 묶음의 첫 말에만 아바타. 이어지는 말은 그 폭만큼 비워 말풍선 왼쪽 선을 맞춘다.
  Widget _avatarSlot(String name, ThreadSlot slot) =>
      slot.showHeader ? _avatar(name) : const SizedBox(width: 30);

  Widget _senderName(String name) => Text(name,
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: T.textSecondary));

  /// 사진 한 장 — 커뮤니티 카드와 같은 4:5 규칙([PostMedia.aspectRatio]): 세로 사진은 4:5 까지
  /// 자르고 원본은 전체 보기(누르면)에서. 길게 누르면 다른 말풍선과 같은 메뉴다.
  Widget _photoTile(ChatMessageItem m, double maxW, {required bool mine}) {
    final media = m.media!;
    return GestureDetector(
      onTap: () => PostMediaViewer.open(context, [media]),
      onLongPress: () => _openMessageActions(m),
      child: ClipRRect(
        key: Key('chat-photo-${m.id}'),
        borderRadius: _photoRadius(mine: mine),
        child: SizedBox(
          width: maxW * _photoWidthFactor,
          child: AspectRatio(
            aspectRatio: media.aspectRatio,
            child: Image.network(media.url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => _photoFallback()),
          ),
        ),
      ),
    );
  }

  Widget _captionBubble(ChatMessageItem m, double maxW, {required bool mine}) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: mine ? _warm : null,
            color: mine ? null : T.cardBg,
            borderRadius: _photoRadius(mine: mine),
            border: mine ? null : Border.all(color: T.cardBorder),
          ),
          child: Text(m.body,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: mine ? Colors.white : T.textPrimary)),
        ),
      );

  static BorderRadius _photoRadius({required bool mine}) => BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(mine ? 16 : 4),
        bottomRight: Radius.circular(mine ? 4 : 16),
      );

  /// 못 받은 사진의 자리 — 말풍선이 흔들리지 않게 같은 크기.
  Widget _photoFallback() => Container(
        color: T.surface,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: T.textMuted),
      );

  Widget _bubbleRow(BuildContext context, ChatMessageItem m, ThreadSlot slot) {
    final maxW = MediaQuery.of(context).size.width * 0.68;
    final mine = _myUserId != null && m.senderUserId == _myUserId;
    final time = _hhmm(m.createdAt);

    // 사진 메시지(#452) — 지워졌거나 가려 접힌 것은 글자 말풍선의 규칙을 그대로 따른다.
    if (m.isImage && m.media != null && !m.deleted && !_isFolded(m)) {
      return _photoRow(context, m, slot, maxW: maxW, mine: mine, time: time);
    }

    if (mine) {
      return Padding(
        padding: EdgeInsets.only(top: _gapAbove(slot)),
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
                    color: T.warmEnd.withValues(alpha: 0.24),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(_bodyOf(m),
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white)),
            ),
          ),
          if (slot.showTime) ...[
            const SizedBox(height: 4),
            Text(time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
          ],
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
      padding: EdgeInsets.only(top: _gapAbove(slot)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatarSlot(m.senderName, slot),
        const SizedBox(width: 9),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (slot.showHeader) ...[_senderName(m.senderName), const SizedBox(height: 4)],
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
                      color: T.cardBg,
                      borderRadius: br,
                      border: Border.all(color: T.cardBorder),
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
            if (slot.showTime) ...[
              const SizedBox(height: 4),
              Text(time, style: const TextStyle(fontSize: 11, color: T.textMuted)),
            ],
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
        // 사진 보내기(#452) — 글자 칸 왼쪽. 앨범에서 고른 사진이 말풍선이 된다.
        GestureDetector(
          key: const Key('chat-photo'),
          onTap: _pickPhotos,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: T.surface,
              shape: BoxShape.circle,
              border: Border.all(color: T.cardBorder),
            ),
            child: const Icon(Icons.photo_outlined, size: 21, color: T.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: T.cardBorder),
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

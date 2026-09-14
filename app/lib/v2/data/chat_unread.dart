// 채팅 탭의 "안 읽은 것 있음" 점 — 이슈 #452.
//
// HIG: 탭 바 뱃지는 정말 중요한 것에만, 개수가 아니라 **점 하나**. 방 목록의 개수 뱃지는 그대로고,
// 탭에는 "볼 것이 있다" 만 말한다. 음소거한 방은 세지 않는다 — 조용히 해 달라고 한 방이 탭을
// 켜면 음소거가 거짓말이 된다.
import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_state.dart';
import 'chat_repository.dart';

class ChatUnread {
  const ChatUnread._();

  /// 안 읽은 방이 하나라도 있나. 탭 바가 듣는다.
  static final ValueNotifier<bool> any = ValueNotifier(false);

  /// 방 목록을 받은 곳(목록 화면 · 감시자)이 부른다 — 서버의 `unread` 가 정본이다. 앱이
  /// `lastSeq - lastReadSeq` 를 다시 세지 않는다(방 목록 화면과 같은 이유).
  static void update(List<ChatRoomSummary> rooms) {
    any.value = rooms.any((r) => r.unread > 0 && !r.muted);
  }

  static void resetForTest() => any.value = false;
}

/// 채팅 탭에 안 가도 점이 켜지게 방 목록을 가끔 본다 — 로그인한 동안 [interval] 마다, 앱이
/// 다시 앞으로 올 때 한 번 더. 게스트면 부르지 않는다. 그리는 것은 없다.
///
/// `GET /api/chat/rooms` 는 레이트리밋 표에 없는 경로다(#80 이 채팅 버킷을 정한다) — 분당
/// 한 번이면 그 표가 생겨도 걸릴 숫자가 아니다.
class ChatUnreadWatcher extends StatefulWidget {
  final ChatRepository? repository;
  final Duration interval;

  const ChatUnreadWatcher({super.key, this.repository, this.interval = const Duration(seconds: 60)});

  @override
  State<ChatUnreadWatcher> createState() => _ChatUnreadWatcherState();
}

class _ChatUnreadWatcherState extends State<ChatUnreadWatcher> with WidgetsBindingObserver {
  late final ChatRepository _repo = widget.repository ?? ChatRepository();
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthState.status.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    AuthState.status.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  /// 로그인 상태가 바뀔 때마다 — 로그인하면 바로 한 번 보고 주기를 건다, 나가면 끄고 점을 지운다.
  void _sync() {
    if (AuthState.isAuthenticated) {
      _timer ??= Timer.periodic(widget.interval, (_) => _tick());
      _tick();
    } else {
      _timer?.cancel();
      _timer = null;
      ChatUnread.any.value = false;
    }
  }

  Future<void> _tick() async {
    if (!mounted || _busy || !AuthState.isAuthenticated) return;
    _busy = true;
    try {
      ChatUnread.update(await _repo.rooms());
    } on ChatFailure {
      // 조용히 — 다음 틱에 다시 본다. 점 하나 때문에 화면을 흔들지 않는다.
    } on Exception {
      // 위와 같다.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

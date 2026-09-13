import 'login_screen.dart';
import '../data/auth_state.dart';
import 'package:flutter/material.dart';

import '../data/chat_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'family_chat_screen.dart';
import 'family_screen.dart';
import 'invite_join_screen.dart';

/// 채팅 탭 — 방 목록. **서버가 준 방을 그대로 그린다.** (이슈 #81)
///
/// 예전에는 `kChatRooms` 더미 둘을 그렸다. 지금은 `GET /api/chat/rooms` 다. 가족방과 산책
/// 크루가 **같은 코드로 돈다** — 방 종류는 서버가 준 `tag` 문자열이고, 화면은 그것을 해석하지
/// 않고 색과 아이콘만 고른다 (ADR-0011).
///
/// 미읽음 뱃지는 **서버가 계산한 `unread`** 다. 앱이 `lastSeq - lastReadSeq` 를 다시 계산하지
/// 않는다 — 두 곳에서 세면 한쪽이 틀리는 날이 온다.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, ChatRepository? repository}) : _injected = repository;

  /// 테스트에서 갈아 끼우기 위한 것. 화면은 평소 [ChatRepository] 기본 생성자를 쓴다.
  final ChatRepository? _injected;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late final ChatRepository _repo = widget._injected ?? ChatRepository();

  List<ChatRoomSummary>? _rooms;
  ChatFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AuthState.status.addListener(_onAuth);
    _load();
  }

  @override
  void dispose() {
    AuthState.status.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    if (AuthState.isGuest) {
      // 게스트는 방이 없는 게 아니라 계정이 없다. 서버를 부르지 않는다(#324).
      setState(() {
        _failure = ChatFailure(ChatFailureKind.unauthorized,
            ChatFailure.messageFor(ChatFailureKind.unauthorized));
        _loading = false;
      });
      return;
    }
    try {
      final rooms = await _repo.rooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } on ChatFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 100),
              children: [
                Row(children: const [
                  Text('채팅',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: T.textPrimary)),
                  Spacer(),
                  ProfileAvatar(),
                ]),
                const SizedBox(height: 4),
                const Text('가족·이웃 반려인들과의 대화',
                    style: TextStyle(fontSize: 13, color: T.textSecondary)),
                const SizedBox(height: 16),
                ..._body(),
                // 로그인 전에는 가족 관리·초대 참여를 보여 주지 않는다 — 눌러도 안 되는 항목이다(#324).
                if (_failure?.kind != ChatFailureKind.unauthorized) ...[
                  const SizedBox(height: 4),
                  _actions(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_failure != null) {
      return [_failureCard(_failure!)];
    }
    final rooms = _rooms ?? const <ChatRoomSummary>[];
    if (rooms.isEmpty) {
      return const [
        GlassCard(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Text('아직 참여한 방이 없어요.\n가족을 만들거나 초대코드로 들어와 보세요.',
              style: TextStyle(fontSize: 13, height: 1.5, color: T.textSecondary)),
        ),
      ];
    }
    return [
      for (final room in rooms) ...[
        _roomCard(context, room),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _failureCard(ChatFailure failure) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(failure.message,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
        const SizedBox(height: 12),
        // 로그인이 필요한 것은 다시 눌러도 안 된다 — 로그인 버튼을 준다(#324).
        if (failure.kind == ChatFailureKind.unauthorized)
          GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            behavior: HitTestBehavior.opaque,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.login_rounded, size: 17, color: T.warmText),
              SizedBox(width: 6),
              Text('로그인',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: T.warmText)),
            ]),
          )
        else
          GestureDetector(
            onTap: _load,
            behavior: HitTestBehavior.opaque,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded, size: 17, color: T.textSecondary),
              SizedBox(width: 6),
              Text('다시 시도',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ]),
          ),
      ]),
    );
  }

  Widget _roomCard(BuildContext context, ChatRoomSummary room) {
    final accent = _accentFor(room.tag);
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FamilyChatScreen(
            roomId: room.id,
            title: room.title,
            subtitle: '${room.memberCount}명',
            isOwner: room.isOwner,
          ),
        ));
        // 방을 보고 나오면 미읽음이 달라진다. 서버가 다시 답하게 한다 —
        // 앱이 0으로 지레짐작하면 읽음 보고가 실패했을 때 뱃지가 거짓말을 한다.
        await _load();
      },
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(_iconFor(room.tag), size: 24, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ),
                if (room.tag.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(room.tag,
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800, color: accent)),
                  ),
                ],
                const SizedBox(width: 6),
                Text('${room.memberCount}명',
                    style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
              const SizedBox(height: 5),
              Text(
                _preview(room),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: T.textMuted),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          if (room.unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [T.warmStart, T.warmEnd]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${room.unread}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
        ]),
      ),
    );
  }

  /// 마지막 메시지 한 줄. 아직 아무도 안 썼으면 그렇게 말한다 — **가짜 문장을 넣지 않는다.**
  ///
  /// 가린 사람이 마지막으로 말했으면 **여기서도 접는다.** 방 안에서 접어 놓고 목록에서
  /// 그대로 보여 주면 가린 말이 거기로 샌다 (#82).
  static String _preview(ChatRoomSummary room) {
    final body = room.lastMessageBody;
    if (body == null || body.isEmpty) {
      return '아직 대화가 없어요';
    }
    if (room.lastMessageHidden) {
      return '가린 사람의 메시지입니다';
    }
    final sender = room.lastMessageSender;
    return sender == null || sender.isEmpty ? body : '$sender · $body';
  }

  /// 방 색. **서버의 `tag` 는 자유 문자열이라 모르는 값이 올 수 있다** — 그때도 화면이
  /// 그려져야 하므로 기본값을 둔다.
  /// 방 종류별 색. `tag` 는 서버가 주는 **사람이 읽는 라벨**이다(`chat_room.tag`).
  ///
  /// '크루' 는 #417 이 실제로 쓰는 값이고, '산책 크루' 는 그 전에 문서·더미가 쓰던 값이라
  /// 둘 다 받는다 — 옛 값을 지우면 예전에 만들어진 방이 회색으로 떨어진다.
  static Color _accentFor(String tag) => switch (tag) {
        '가족' => T.warmMid,
        '크루' || '산책 크루' => const Color(0xFF57C98A),
        _ => T.accent,
      };

  static IconData _iconFor(String tag) => switch (tag) {
        '가족' => Icons.diversity_1_rounded,
        '크루' || '산책 크루' => Icons.directions_walk_rounded,
        _ => Icons.forum_rounded,
      };

  Widget _actions(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
        behavior: HitTestBehavior.opaque,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: const [
            Icon(Icons.diversity_1_rounded, size: 19, color: T.warmMid),
            SizedBox(width: 10),
            Expanded(
              child: Text('우리 가족 관리 — 멤버·초대·오늘의 케어',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: T.textSecondary)),
            ),
            Icon(Icons.chevron_right, size: 18, color: T.textFaint),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () async {
          final joined = await Navigator.of(context)
              .push<bool>(MaterialPageRoute(builder: (_) => const InviteJoinScreen()));
          if (joined == true) {
            await _load();
          }
        },
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: T.cardBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.vpn_key_outlined, size: 18, color: T.textSecondary),
            SizedBox(width: 8),
            Text('초대코드로 참여',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
          ]),
        ),
      ),
    ]);
  }
}

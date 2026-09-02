import 'package:flutter/material.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';

/// 글 상세 (postDetail) — 커뮤니티 글 1건 + 반응 + 댓글 스레드.
///
/// **서버에서 온다** (이슈 #171). 2026-09 이전에는 반응이 화면 로컬 토글이었고 댓글은
/// `_cmts` 리스트에만 쌓였다 — 화면을 나가면 사라졌고, 그 사실을 이 파일이 스스로
/// "화면 로컬 더미 댓글 모델. (추후 백엔드 연동)" 이라고 적고 있었다.
///
/// ## 게스트인지 서버에게 묻는다
///
/// `post.reactions.mine` 이 `null` 이면 게스트다. `AuthState` 를 안 보는 이유는, 그
/// 값과 이 응답이 어긋날 수 있어서다 — 토큰이 만료된 채 읽기만 하면 앱은 자기가
/// 로그인했다고 믿지만 서버는 게스트로 대접한다. 화면은 **서버가 방금 말한 것**을
/// 따른다.
class PostDetailScreen extends StatefulWidget {
  final CommunityPost post;

  /// 목록 화면이 자기 리포지토리를 넘긴다. 테스트는 가짜 서버를 넣는다.
  final CommunityRepository? repository;

  const PostDetailScreen({super.key, required this.post, this.repository});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _ctrl = TextEditingController();

  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  late CommunityPost _post = widget.post;

  List<CommunityComment> _comments = const [];
  bool _loadingComments = true;
  CommunityFailure? _commentsFailure;

  /// 반응·댓글을 보내는 중. 두 번 눌러 두 줄이 되는 것을 막는다.
  bool _sending = false;

  static const _avatarColors = [
    [Color(0xFF8FB6FF), Color(0xFF5B79F5)],
    [Color(0xFFBBA0FF), Color(0xFF7E68F0)],
    [Color(0xFF7FE6CC), Color(0xFF33BFA6)],
    [Color(0xFFFF9FCF), Color(0xFFCE7DF5)],
  ];

  static const _warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  /// 서버가 방금 이 요청을 게스트로 봤는가.
  bool get _isGuest => _post.reactions.mine == null;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsFailure = null;
    });
    try {
      final page = await _repo.comments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _loadingComments = false;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _commentsFailure = failure;
        _loadingComments = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _repo.addComment(_post.id, text);
      if (!mounted) return;
      setState(() {
        // 목록의 끝에 붙인다 — 댓글은 오래된 것부터라 새 것이 마지막이다.
        _comments = [..._comments, comment];
        _ctrl.clear();
        _sending = false;
      });
      FocusScope.of(context).unfocus();
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  /// 반응을 누르거나 뗀다.
  ///
  /// **낙관적 갱신을 안 한다.** 서버가 멱등한 응답으로 집계를 돌려주므로 그것을
  /// 그대로 그린다 — 로컬에서 세면 남이 같은 시간에 누른 것이 안 보이고, 실패했을 때
  /// 되돌릴 자리가 생긴다.
  Future<void> _toggleReaction(CommunityReaction reaction) async {
    if (_sending) return;
    if (_isGuest) {
      _toast(CommunityFailureKind.unauthorized.message);
      return;
    }
    setState(() => _sending = true);
    try {
      final summary = _post.reactions.isMine(reaction)
          ? await _repo.removeReaction(_post.id, reaction)
          : await _repo.addReaction(_post.id, reaction);
      if (!mounted) return;
      setState(() {
        _post = _withReactions(_post, summary);
        _sending = false;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(failure.message);
    }
  }

  static CommunityPost _withReactions(
    CommunityPost post,
    ReactionSummary reactions,
  ) =>
      CommunityPost(
        id: post.id,
        author: post.author,
        board: post.board,
        title: post.title,
        body: post.body,
        loc: post.loc,
        contentId: post.contentId,
        commentCount: post.commentCount,
        reactions: reactions,
        createdAt: post.createdAt,
      );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 헤더 (뒤로가기)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(
                  children: [
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
                        child: const Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: T.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      '산책 이야기',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                  children: [
                    _postCard(post),
                    const SizedBox(height: 14),
                    _reactionRow(),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(
                          Icons.forum_outlined,
                          size: 17,
                          color: Color(0xFFFF8F63),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '댓글 ${_comments.length}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: T.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._commentSection(),
                  ],
                ),
              ),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// 댓글 자리. 못 불러왔으면 **빈 스레드가 아니라 이유**를 그린다 — 빈 스레드는
  /// "아직 댓글이 없다" 로 읽힌다.
  List<Widget> _commentSection() {
    if (_loadingComments) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final failure = _commentsFailure;
    if (failure != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            Text(failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary)),
            if (failure.retryable) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _loadComments,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                      gradient: _warm, borderRadius: BorderRadius.circular(12)),
                  child: const Text('다시 시도',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ],
          ]),
        ),
      ];
    }
    if (_comments.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('첫 댓글을 남겨보세요.',
                style: TextStyle(color: T.textMuted)),
          ),
        ),
      ];
    }
    return [
      for (final comment in _comments) ...[
        _commentCard(comment),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _avatar(String nickname, double size) {
    final colors =
        _avatarColors[nickname.hashCode.abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 상세의 날짜. 목록과 달리 시각까지 그린다 — 스레드를 읽는 사람은 순서를 본다.
  static String _dateTime(DateTime at) =>
      '${at.year % 100}.${at.month.toString().padLeft(2, '0')}.'
      '${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  Widget _postCard(CommunityPost post) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 작성자
          Row(
            children: [
              _avatar(post.author.nickname, 44),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.nickname,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _boardChip(post.board),
                        if (post.loc != null) ...[
                          const SizedBox(width: 7),
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: T.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            post.loc!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: T.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                _dateTime(post.createdAt),
                style: const TextStyle(fontSize: 11.5, color: T.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 제목
          Text(
            post.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // 본문
          Text(
            post.body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xCC463C64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardChip(CommunityBoard? board) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x1AFF8F63),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pets, size: 11, color: Color(0xFFE07A4E)),
          const SizedBox(width: 4),
          Text(
            board?.label ?? '기타',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE07A4E),
            ),
          ),
        ],
      ),
    );
  }

  /// 반응 셋. **동시에 여러 개를 누를 수 있다**(ADR-0016 결정 2) — 서로 배타적인
  /// 개념이 아니라서 하나만 켜지는 라디오로 만들지 않는다.
  Widget _reactionRow() {
    const icons = {
      CommunityReaction.help: Icons.thumb_up_alt_outlined,
      CommunityReaction.cute: Icons.favorite_outline,
      CommunityReaction.empathy: Icons.emoji_emotions_outlined,
    };
    return Row(
      children: [
        for (final reaction in CommunityReaction.values) ...[
          if (reaction != CommunityReaction.values.first)
            const SizedBox(width: 9),
          Expanded(child: _reactionBtn(reaction, icons[reaction]!)),
        ],
      ],
    );
  }

  Widget _reactionBtn(CommunityReaction reaction, IconData icon) {
    // 게스트에게는 **꺼진 채로** 그린다. mine 이 null 인 것을 "안 눌렀음" 으로
    // 뭉개면 로그인한 사람의 화면과 구별되지 않는다.
    final on = _post.reactions.isMine(reaction);
    return GestureDetector(
      onTap: () => _toggleReaction(reaction),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: on ? _warm : null,
          color: on ? null : const Color(0xC9FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? Colors.transparent : const Color(0x1F8C7BFF),
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: on ? Colors.white : T.textSecondary),
            const SizedBox(width: 6),
            Text(
              reaction.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : T.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${_post.reactions.countOf(reaction)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : T.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(CommunityComment comment) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(comment.author.nickname, 34),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.author.nickname,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _dateTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: T.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xCC463C64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    // 게스트에게 입력칸을 주고 보낼 때 401 을 내면, 쓴 글자를 잃고 나서야 로그인이
    // 필요한 것을 안다. 아예 안 그린다.
    if (_isGuest) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xF0FFFFFF),
          border: Border(top: BorderSide(color: Color(0x22785AA0))),
        ),
        child: const Text(
          '로그인하면 댓글과 반응을 남길 수 있어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: T.textSecondary,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xF0FFFFFF),
        border: Border(top: BorderSide(color: Color(0x22785AA0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1ECF7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _ctrl,
                maxLength: CommunityRepository.maxCommentLength,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 14, color: T.textPrimary),
                decoration: const InputDecoration(
                  hintText: '우리 아이 이야기를 나눠보세요',
                  hintStyle: TextStyle(fontSize: 14, color: T.textMuted),
                  border: InputBorder.none,
                  counterText: '',
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _warm,
                color: _sending ? T.textMuted : null,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

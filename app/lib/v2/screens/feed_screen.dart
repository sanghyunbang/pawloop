import 'package:flutter/material.dart';
import '../data/community_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/profile_avatar.dart';
import 'post_detail_screen.dart';
import 'post_write_screen.dart';

/// 커뮤니티 (feed) — 반려인들의 산책·동반장소·건강 이야기. 카드/리스트 토글.
///
/// **서버에서 온다** (이슈 #171). 2026-09 이전에는 `kPetPosts` 상수 4건을 걸렀고,
/// 그래서 누가 글을 써도 아무에게도 안 보였다.
///
/// 게시판 칩의 한글은 **화면 문구**다. 서버로 나가는 값은 `CommunityBoard.wire`
/// (`walk_review` 등)이고 둘을 묶어 두는 자리는 그 enum 하나다(ADR-0016).
class FeedScreen extends StatefulWidget {
  /// 테스트가 가짜 서버를 넣는 자리. 앱에서는 `null` 이라 기본 리포지토리가 선다.
  final CommunityRepository? repository;

  const FeedScreen({super.key, this.repository});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();

  /// `null` 이면 전체.
  CommunityBoard? _board;
  String _view = 'card'; // 'card' | 'list'

  List<CommunityPost> _posts = const [];
  String? _nextCursor;
  bool _hasMore = false;

  bool _loading = true;
  bool _loadingMore = false;

  /// 못 불러온 이유. **빈 목록으로 그리지 않는다** — 빈 목록은 "아직 글이 없다" 로
  /// 읽히고, 그러면 서버가 죽은 것을 아무도 모른다.
  CommunityFailure? _failure;

  static const _warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [Color(0xFFFFA96B), Color(0xFFFF7E8A)],
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.feed(board: _board);
      if (!mounted) return;
      setState(() {
        _posts = page.items;
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on CommunityFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.feed(board: _board, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...page.items];
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on CommunityFailure {
      // 다음 장을 못 받은 것은 첫 장까지 지울 이유가 아니다. 버튼만 되살린다.
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectBoard(CommunityBoard? board) {
    if (_board == board) return;
    setState(() => _board = board);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.lilacTop,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                const Text('커뮤니티',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: T.textPrimary)),
                const Spacer(),
                _viewToggle(),
                const SizedBox(width: 10),
                const ProfileAvatar(),
              ]),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('우리 아이들 이야기',
                    style: TextStyle(fontSize: 13, color: Color(0xB3463C64))),
              ),
            ),
            const SizedBox(height: 10),
            _boardFilter(),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final failure = _failure;
    if (failure != null) {
      return _failureView(failure);
    }
    if (_posts.isEmpty) {
      return _emptyView();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            12, 4, 12, MediaQuery.of(context).padding.bottom + 100),
        children: [
          for (final post in _posts) ...[
            _view == 'card' ? _card(post) : _row(post),
            SizedBox(height: _view == 'card' ? 14 : 10),
          ],
          if (_hasMore) _moreButton(),
        ],
      ),
    );
  }

  /// 글이 하나도 없을 때.
  ///
  /// **'불러오지 못했어요' 와 다른 문구여야 한다.** 빈 것과 못 불러온 것은 사용자가 할 일이
  /// 다르다 — 하나는 쓰면 되고 하나는 기다리면 된다. `pet.dart` 가 산책 더미를 지우며 남긴
  /// 규칙이 같은 말을 한다: "0 은 '산책을 한 번도 안 했다' 로 읽힌다".
  ///
  /// 어느 게시판이 비었는지 말한다. '자유' 를 골랐는데 그냥 "글이 없어요" 라고만 하면
  /// 앱 전체가 빈 것처럼 읽힌다(#173).
  Widget _emptyView() {
    final board = _board;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            board == null
                ? '아직 글이 없어요'
                : '아직 ${board.label} 게시판에 글이 없어요',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text('첫 이야기를 남겨보세요',
              style: TextStyle(fontSize: 13, color: T.textMuted)),
          const SizedBox(height: 14),
          _writeButton(label: '글쓰기', big: true),
        ]),
      ),
    );
  }

  /// 글쓰기로 가는 버튼. 두 자리에서 같은 것을 쓴다 — 게시판 줄과 빈 화면.
  ///
  /// 떠 있는 FAB 을 안 만든 이유는 셸이 화면 위에 네비 띠를 덮기 때문이다
  /// (`main_shell` 의 알약이 bottom+8~74, 가운데 버튼이 bottom+38~96). 그 띠는 Stack 의
  /// **마지막** 자식이라 그 안에 그린 것은 눌리지 않는다.
  Widget _writeButton({required String label, bool big = false}) {
    return GestureDetector(
      onTap: _openWrite,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: big ? 20 : 13, vertical: big ? 11 : 7),
        decoration: BoxDecoration(
            gradient: _warm, borderRadius: BorderRadius.circular(big ? 14 : 11)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_outlined, size: big ? 17 : 14, color: Colors.white),
          SizedBox(width: big ? 7 : 5),
          Text(label,
              style: TextStyle(
                  fontSize: big ? 14 : 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      ),
    );
  }

  /// 글쓰기 화면을 연다. 미로그인 판정은 [writePost] 안에 한 곳만 있다.
  ///
  /// 방금 쓴 글이 목록에 보여야 한다(#172 완료 조건 6). 지금 고른 게시판을 들고 가서
  /// 사용자가 다시 고르지 않게 한다.
  Future<void> _openWrite() async {
    final written = await writePost(
      context,
      repository: _repo,
      initialBoard: _board,
    );
    if (!mounted || written == null) return;
    await _load();
  }

  /// 못 불러왔을 때의 화면.
  ///
  /// 빈 목록이 아니라 **이유와 다시 시도**다. `pet.dart` 가 산책 더미를 지우며 남긴
  /// 규칙이 그것이다 — "0 은 '산책을 한 번도 안 했다' 로 읽힌다".
  Widget _failureView(CommunityFailure failure) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 34, color: T.textMuted),
          const SizedBox(height: 12),
          Text(
            failure.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary),
          ),
          if (failure.retryable) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    gradient: _warm, borderRadius: BorderRadius.circular(13)),
                child: const Text('다시 시도',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _moreButton() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Center(
          child: GestureDetector(
            onTap: _loadingMore ? null : _loadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xCCFFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: Text(_loadingMore ? '불러오는 중…' : '더 보기',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
            ),
          ),
        ),
      );

  Widget _viewToggle() {
    Widget seg(String value, IconData icon) {
      final on = _view == value;
      return GestureDetector(
        onTap: () => setState(() => _view = value),
        child: Container(
          width: 42,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              gradient: on ? _warm : null,
              borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 20, color: on ? Colors.white : T.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xC2FFFFFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(children: [
        seg('card', Icons.view_agenda_outlined),
        seg('list', Icons.format_list_bulleted),
      ]),
    );
  }

  // 보드 필터: 가로로 무한정 늘지 않도록 '전체 ▾' 버튼 + 바텀시트.
  Widget _boardFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        GestureDetector(
          onTap: _openBoardSheet,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xCCFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tune, size: 16, color: T.textSecondary),
              const SizedBox(width: 7),
              Text(_board?.label ?? '전체',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: T.textSecondary)),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more, size: 16, color: T.textMuted),
            ]),
          ),
        ),
        const Spacer(),
        if (_failure == null) ...[
          Text('${_posts.length}개의 글',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: T.textMuted)),
          const SizedBox(width: 10),
        ],
        _writeButton(label: '글쓰기'),
      ]),
    );
  }

  void _openBoardSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
            color: Color(0xFAFCFAFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 18 + MediaQuery.of(sheetCtx).padding.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                          color: const Color(0x2E281E30),
                          borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 16),
              const Text('게시판',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: T.textPrimary)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _boardOption(sheetCtx, null, '전체'),
                for (final board in CommunityBoard.values)
                  _boardOption(sheetCtx, board, board.label),
              ]),
            ]),
      ),
    );
  }

  Widget _boardOption(BuildContext sheetCtx, CommunityBoard? board, String label) {
    final on = _board == board;
    return GestureDetector(
      onTap: () {
        Navigator.pop(sheetCtx);
        _selectBoard(board);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          gradient: on ? _warm : null,
          color: on ? null : const Color(0xFFF1ECF7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : T.textSecondary)),
      ),
    );
  }

  Future<void> _open(CommunityPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post, repository: _repo),
      ),
    );
    // 상세에서 댓글·반응이 늘었을 수 있다. 목록의 숫자가 낡은 채 남지 않게 한다.
    if (mounted) await _load();
  }

  // 닉네임 원형 아바타 (닉 첫 글자, 따뜻한 그라데이션).
  Widget _avatar(CommunityPost post, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, gradient: _warm),
        child: Text(_initial(post.author.nickname),
            style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      );

  /// 아바타 글자. 닉네임이 빈 문자열이면 `characters.first` 가 던진다 — 서버가
  /// 탈퇴한 사람에게 '알 수 없음' 을 주므로 빈 값이 올 일은 없지만, 카드 하나 때문에
  /// 목록이 죽는 것은 막는다.
  static String _initial(String nickname) =>
      nickname.isEmpty ? '?' : nickname.characters.first;

  /// 보드별 색. 키가 아니라 enum 으로 가른다 — 문자열로 가르면 서버가 값을 바꿀 때
  /// `default` 로 조용히 떨어진다.
  Color _boardColor(CommunityBoard? board) => switch (board) {
        CommunityBoard.walkReview => const Color(0xFF33BFA6),
        CommunityBoard.petPlace => const Color(0xFFFF7E6B),
        CommunityBoard.health => const Color(0xFF5B8DEF),
        CommunityBoard.free => const Color(0xFF9B7BFF),
        CommunityBoard.brag => const Color(0xFFEFA13C),
        null => const Color(0xFFFF8F63),
      };

  Widget _boardChip(CommunityBoard? board) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: _boardColor(board).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8)),
        child: Text(board?.label ?? '기타',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _boardColor(board))),
      );

  /// 목록의 날짜. 시각까지는 안 그린다 — 카드 한 줄에 들어가야 한다.
  static String _date(DateTime at) =>
      '${at.year % 100}.${at.month.toString().padLeft(2, '0')}.'
      '${at.day.toString().padLeft(2, '0')}';

  Widget _card(CommunityPost post) {
    return GestureDetector(
      onTap: () => _open(post),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(post, 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(post.author.nickname,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: T.textPrimary)),
                      const Spacer(),
                      Text(_date(post.createdAt),
                          style: const TextStyle(
                              fontSize: 11.5, color: T.textMuted)),
                    ]),
                    const SizedBox(height: 5),
                    Row(children: [
                      _boardChip(post.board),
                      if (post.loc != null) ...[
                        const SizedBox(width: 7),
                        const Icon(Icons.place_outlined,
                            size: 13, color: T.textMuted),
                        const SizedBox(width: 2),
                        Text(post.loc!,
                            style: const TextStyle(
                                fontSize: 11.5, color: T.textMuted)),
                      ],
                    ]),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(post.title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: T.textPrimary)),
          const SizedBox(height: 5),
          Text(post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: Color(0xCC463C64))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final reaction in CommunityReaction.values)
              _reactionChip(reaction, post.reactions),
          ]),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0x14785AA0)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.chat_bubble_outline, size: 16, color: T.textMuted),
            const SizedBox(width: 6),
            Text('댓글 ${post.commentCount}개 · 자세히 보기',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: T.textSecondary)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ]),
      ),
    );
  }

  Widget _reactionChip(CommunityReaction reaction, ReactionSummary summary) {
    final count = summary.countOf(reaction);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x80FFFFFF),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(reaction.label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: T.textSecondary)),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Text('$count',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: T.textMuted)),
        ],
      ]),
    );
  }

  Widget _row(CommunityPost post) {
    return GestureDetector(
      onTap: () => _open(post),
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
        child: Row(children: [
          _avatar(post, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: T.textPrimary)),
                  const SizedBox(height: 5),
                  Row(children: [
                    _boardChip(post.board),
                    if (post.loc != null) ...[
                      const SizedBox(width: 7),
                      const Icon(Icons.place_outlined,
                          size: 12, color: T.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(post.loc!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: T.textMuted)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    const Icon(Icons.chat_bubble_outline,
                        size: 13, color: T.textMuted),
                    const SizedBox(width: 3),
                    Text('${post.commentCount}',
                        style: const TextStyle(
                            fontSize: 12, color: T.textMuted)),
                  ]),
                ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
        ]),
      ),
    );
  }
}

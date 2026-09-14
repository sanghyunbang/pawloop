// 저장한 글 — "내 사진첩" (이슈 #451 4번).
//
// 카드·상세의 책갈피로 저장해 둔 글이 **저장한 순**으로 모인다(글이 쓰인 순이 아니다 —
// Instagram 의 저장됨). 사진 있는 글은 사진 벽으로, 글만 있는 글은 그 아래 한 줄씩. 벽은
// 커뮤니티의 것을 그대로 쓴다 — 여기서는 하트 알약을 안 붙인다(구경하고 다시 찾는 곳이다).
//
// 서버가 "내 것" 만 준다 — 경로에 사람이 없다. 게스트가 열면 401 이고 그 말을 그대로 보여 준다.
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/community_repository.dart';
import '../domain/date_label.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/post_photo_wall.dart';
import 'post_detail_screen.dart';

class SavedPostsScreen extends StatefulWidget {
  final CommunityRepository? repository;

  const SavedPostsScreen({super.key, this.repository});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  late final CommunityRepository _repo = widget.repository ?? CommunityRepository();

  List<CommunityPost> _posts = const [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  CommunityFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 게스트는 서버를 부르지 않는다 — 401 을 받아 오는 것과 화면은 같지만, 부르지 않아야
    // 내 정보 화면의 테스트가 진짜 네트워크 타이머를 남기지 않는다(홈의 이웃 사진 줄과 같은 문).
    if (AuthState.isGuest) {
      setState(() {
        _loading = false;
        _failure = const CommunityFailure(CommunityFailureKind.unauthorized);
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.bookmarks(limit: 20);
      if (!mounted) return;
      setState(() {
        _posts = page.items;
        _cursor = page.nextCursor;
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
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.bookmarks(cursor: cursor, limit: 20);
      if (!mounted) return;
      setState(() {
        _posts = [..._posts, ...page.items];
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on CommunityFailure {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 상세에서 저장을 뺐으면 목록에서도 빠져야 한다 — 돌아올 때 다시 읽는다.
  Future<void> _open(CommunityPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post, repository: _repo)),
    );
    if (mounted && changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
              child: Row(children: [
                IconButton(
                  key: const Key('saved-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
                ),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('저장한 글',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, color: T.textPrimary)),
                    Text('내 사진첩 · 저장한 순',
                        style: TextStyle(fontSize: 12.5, color: T.textMuted)),
                  ]),
                ),
              ]),
            ),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final failure = _failure;
    if (failure != null) return _failureView(failure);
    if (_posts.isEmpty) return _emptyView();
    final withMedia = PostPhotoWall.withMedia(_posts);
    final textOnly = _posts.where((p) => p.media.isEmpty).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('saved-list'),
        padding: EdgeInsets.fromLTRB(12, 4, 12, MediaQuery.of(context).padding.bottom + 24),
        children: [
          if (withMedia.isNotEmpty) PostPhotoWall(posts: withMedia, onTap: _open),
          if (withMedia.isNotEmpty && textOnly.isNotEmpty) const SizedBox(height: 6),
          for (final post in textOnly) ...[
            _row(post),
            const SizedBox(height: 10),
          ],
          if (_hasMore) _moreButton(),
        ],
      ),
    );
  }

  /// 글만 있는 글 — 제목 · 게시판 · 날짜 한 줄.
  Widget _row(CommunityPost post) => GestureDetector(
        key: Key('saved-row-${post.id}'),
        onTap: () => _open(post),
        behavior: HitTestBehavior.opaque,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: T.textPrimary)),
                const SizedBox(height: 4),
                Text('${post.board?.label ?? '기타'} · ${post.author.nickname} · ${dateLabel(post.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ),
      );

  Widget _emptyView() => Center(
        key: const Key('saved-empty'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.bookmark_border_rounded, size: 36, color: T.textMuted),
            SizedBox(height: 12),
            Text('저장한 글이 없어요',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textSecondary)),
            SizedBox(height: 6),
            Text('카드나 글의 책갈피를 누르면 여기에 모여요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: T.textMuted)),
          ]),
        ),
      );

  Widget _failureView(CommunityFailure failure) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 34, color: T.textMuted),
            const SizedBox(height: 12),
            Text(failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
            if (failure.retryable) ...[
              const SizedBox(height: 14),
              GestureDetector(
                key: const Key('saved-retry'),
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: T.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: T.cardBorder),
                  ),
                  child: const Text('다시 시도',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
                ),
              ),
            ],
          ]),
        ),
      );

  Widget _moreButton() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Center(
          child: GestureDetector(
            key: const Key('saved-more'),
            onTap: _loadingMore ? null : _loadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: T.cardBorder),
              ),
              child: Text(_loadingMore ? '불러오는 중…' : '더 보기',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
          ),
        ),
      );
}

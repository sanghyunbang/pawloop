// 이 장소의 글 — 이슈 #723 (조각 2).
//
// 사장님 발견: 장소에 대해 글을 쓸 수는 있는데(`이 장소로 글쓰기`, #172) 그 장소의 글을 **모아 볼 길이
// 없었다.** 서버가 `?contentId=` 로 좁혀 준다(글은 공개라 게스트도 본다). 사진 있는 글은 사진 벽으로,
// 글만 있는 글은 한 줄씩 — 아이 사진첩(`dog_gallery_screen.dart`)과 같은 모양이다.
//
// 아이 사진첩과 다른 점 하나: **토큰 문이 없다.** 그 화면은 "내 정보" 에서만 열려 토큰이 없으면 서버를
// 안 불렀지만, 장소는 지도와 홈에서 게스트도 누른다. 글이 공개인데 로그인을 요구하면 그건 문이 아니라 벽이다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../domain/date_label.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/post_photo_wall.dart';
import 'post_detail_screen.dart';
import 'post_write_screen.dart';

class PlacePostsScreen extends StatefulWidget {
  /// `Place.contentId` — 글의 `contentId` 와 같은 키(ADR-0017).
  final String contentId;
  final String title;
  final CommunityRepository? repository;

  const PlacePostsScreen({super.key, required this.contentId, required this.title, this.repository});

  @override
  State<PlacePostsScreen> createState() => _PlacePostsScreenState();
}

class _PlacePostsScreenState extends State<PlacePostsScreen> {
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
    // 상세에서 저장 · 반응 · 댓글이 바뀌거나 여기서 글을 쓰면 다시 읽는다 — 어떻게 나왔든(#548).
    kCommunityRev.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    kCommunityRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.feed(contentId: widget.contentId, limit: 30);
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
      final page = await _repo.feed(contentId: widget.contentId, cursor: cursor, limit: 30);
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

  Future<void> _open(CommunityPost post) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post, repository: _repo)),
    );
  }

  /// 이 장소를 물고 글쓰기로 — 빈 화면의 첫 글도, 목록 위의 글쓰기도 같은 문이다.
  Future<void> _write() async {
    await writePost(
      context,
      repository: _repo,
      initialBoard: CommunityBoard.petPlace,
      loc: widget.title,
      contentId: widget.contentId,
    );
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
                  key: const Key('place-posts-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${widget.title}의 글',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: T.textPrimary)),
                    const Text('이 장소를 골라 쓴 커뮤니티 글',
                        style: TextStyle(fontSize: 12, color: T.textMuted)),
                  ]),
                ),
                IconButton(
                  key: const Key('place-posts-write'),
                  onPressed: _write,
                  tooltip: '이 장소로 글쓰기',
                  icon: const Icon(Icons.edit_outlined, color: T.textPrimary),
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
        key: const Key('place-posts-list'),
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

  Widget _row(CommunityPost post) => GestureDetector(
        key: Key('place-posts-row-${post.id}'),
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
                Text('${post.board?.label ?? '기타'} · ${dateLabel(post.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: T.textMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: T.textMuted),
          ]),
        ),
      );

  /// 글이 없는 장소 — "없다" 로 끝내지 않고 첫 글의 문을 연다.
  Widget _emptyView() => Center(
        key: const Key('place-posts-empty'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.edit_note_rounded, size: 36, color: T.textMuted),
            const SizedBox(height: 12),
            const Text('아직 이 장소의 글이 없어요',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textSecondary)),
            const SizedBox(height: 6),
            Text('${widget.title}에 다녀온 이야기를 첫 글로 남겨 주세요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: T.textMuted)),
            const SizedBox(height: 16),
            GestureDetector(
              key: const Key('place-posts-write-first'),
              onTap: _write,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [T.warmStart, T.warmEnd]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('이 장소로 글쓰기',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
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
                key: const Key('place-posts-retry'),
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
            key: const Key('place-posts-more'),
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

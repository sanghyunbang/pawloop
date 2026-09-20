// 이 장소의 글 — 장소 페이지. 이슈 #723(조각 2) → #729(사진 | 글 · 머리 · 정렬).
//
// 사장님 지적: 목록일 뿐이었다 — 작성자도 본문도 반응도 정렬도 장소 정보도 없었다. 네이버 플레이스
// 리뷰 탭(사진 그리드 → 리뷰 카드 · 정렬)과 인스타그램 위치 페이지(장소 머리 · 숫자 · 그리드)를 참고해
// 이렇게 짰다.
//
//   - **머리**: 장소 사진(없으면 분류색 바탕) · 이름 · 분류 칩 · 거리 · 주소 · "글 N · 사진 N · 산책 N회"
//     (서버 집계 `GET /api/community/places/{contentId}/summary`). 사장님 결정: 갈래는 **사진 | 글 둘**.
//   - **사진 갈래**: 사진 있는 글의 사진 벽(`PostPhotoWall`). **글 갈래**: 커뮤니티 피드와 **같은 카드**
//     (`PostCard`) — 작성자 · 아이 · 본문 두 줄 · 사진 · 반응 · 댓글. 동작도 같다(`PostListActions`).
//   - **정렬**: 최신(기본) · 반응 많은 순 — 받아 둔 장 안에서 정렬한다. 목록 API 는 커서로 최신순만 주고
//     반응 수 정렬을 모르므로, 장소의 글이 한 장을 넘으면 '더 보기' 뒤에 다시 정렬된다. 서버 정렬은 반응
//     수 컬럼이 생길 때.
//   - **바닥 고정** '이 장소로 글쓰기' — 빈 화면이든 목록이든 늘 같은 자리.
//
// 서버가 `?contentId=` 로 좁혀 준다(글은 공개라 게스트도 본다). 아이 사진첩과 달리 **토큰 문이 없다** —
// 장소는 지도와 홈에서 게스트도 누른다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../data/pet_places_repository.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/place_sheet.dart' show placeCategoryTag, placePhotoFallback;
import '../widgets/post_card.dart';
import '../widgets/post_photo_wall.dart';
import 'post_detail_screen.dart';
import 'post_list_actions.dart';
import 'post_write_screen.dart';

/// 갈래 둘 — 사장님 결정(#729).
enum PlacePostsTab { photos, posts }

/// 정렬 둘. 반응 많은 순은 받아 둔 장 안에서다(파일 머리 참조).
enum PlacePostsSort { latest, reactions }

class PlacePostsScreen extends StatefulWidget {
  /// `Place.contentId` — 글의 `contentId` 와 같은 키(ADR-0017).
  final String contentId;
  final String title;

  /// 장소 머리의 재료(사진 · 분류 · 거리 · 주소). 시트에서 오면 있고, 없으면 이름만 그린다.
  final PetPlace? place;
  final CommunityRepository? repository;

  const PlacePostsScreen({
    super.key,
    required this.contentId,
    required this.title,
    this.place,
    this.repository,
  });

  @override
  State<PlacePostsScreen> createState() => _PlacePostsScreenState();
}

class _PlacePostsScreenState extends State<PlacePostsScreen> with PostListActions<PlacePostsScreen> {
  late final CommunityRepository _repo = widget.repository ?? CommunityRepository();

  List<CommunityPost> _posts = const [];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  CommunityFailure? _failure;
  PlaceSummary? _summary;
  PlacePostsTab _tab = PlacePostsTab.photos;
  PlacePostsSort _sort = PlacePostsSort.latest;

  @override
  CommunityRepository get postsRepo => _repo;
  @override
  List<CommunityPost> get posts => _posts;
  @override
  set posts(List<CommunityPost> value) => _posts = value;

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
      // 숫자와 목록을 같이 받는다 — 숫자가 먼저 오고 목록이 늦으면 "글 3" 아래가 비어 보인다.
      final results = await Future.wait([
        _repo.feed(contentId: widget.contentId, limit: 30),
        _repo.placeSummary(widget.contentId),
      ]);
      if (!mounted) return;
      final page = results[0] as CommunityPage<CommunityPost>;
      setState(() {
        _posts = page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _summary = results[1] as PlaceSummary;
        _loading = false;
        // 사진이 하나도 없으면 사진 갈래는 빈 벽이다 — 글 갈래를 먼저 연다.
        if (PostPhotoWall.withMedia(page.items).isEmpty) _tab = PlacePostsTab.posts;
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

  /// 이 장소를 물고 글쓰기로 — 바닥 버튼과 빈 화면이 같은 문이다.
  Future<void> _write() async {
    await writePost(
      context,
      repository: _repo,
      initialBoard: CommunityBoard.petPlace,
      loc: widget.title,
      contentId: widget.contentId,
    );
  }

  /// 정렬된 목록. 반응 많은 순은 세 반응의 합, 같으면 최신이 먼저.
  List<CommunityPost> get _sorted {
    if (_sort == PlacePostsSort.latest) return _posts;
    final out = [..._posts];
    out.sort((a, b) {
      final d = _reactionTotal(b) - _reactionTotal(a);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  static int _reactionTotal(CommunityPost post) =>
      CommunityReaction.values.fold(0, (sum, r) => sum + post.reactions.countOf(r));

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(children: [
                IconButton(
                  key: const Key('place-posts-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
                ),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: T.textPrimary)),
                ),
              ]),
            ),
            Expanded(child: _body()),
            // 바닥 고정 — 빈 화면이든 목록이든 늘 같은 자리(#729).
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
              child: GestureDetector(
                key: const Key('place-posts-write'),
                onTap: _write,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [T.warmStart, T.warmEnd]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, size: 17, color: Colors.white),
                    SizedBox(width: 7),
                    Text('이 장소로 글쓰기',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final failure = _failure;
    if (failure != null) return _failureView(failure);
    final withMedia = PostPhotoWall.withMedia(_posts);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('place-posts-list'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [
          _header(),
          const SizedBox(height: 12),
          _tabs(),
          const SizedBox(height: 10),
          if (_tab == PlacePostsTab.photos) ...[
            if (withMedia.isEmpty) _emptyView(photos: true) else PostPhotoWall(posts: withMedia, onTap: _open),
          ] else ...[
            if (_posts.isEmpty)
              _emptyView(photos: false)
            else ...[
              _sortRow(),
              const SizedBox(height: 8),
              for (final post in _sorted) ...[
                PostCard(
                  key: Key('place-post-${post.id}'),
                  post: post,
                  folded: MediaQuery.textScalerOf(context).scale(11) >= 11 * 1.3,
                  burst: burstOf(post),
                  onOpen: () => _open(post),
                  onDoubleTapLike: () => doubleTapLike(post),
                  onToggleReaction: (reaction) => toggleReaction(post, reaction),
                  onToggleBookmark: () => toggleBookmark(post),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
          if (_hasMore) _moreButton(),
        ],
      ),
    );
  }

  /// 장소 머리 — 사진 · 이름 · 분류 · 거리 · 주소 · 숫자 셋.
  Widget _header() {
    final p = widget.place;
    final cat = p?.petCategory;
    final s = _summary;
    return GlassCard(
      key: const Key('place-posts-header'),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 2.2,
              child: p.image.isEmpty
                  ? placePhotoFallback(cat!, 'page-${p.contentId}')
                  : Image.network(p.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placePhotoFallback(cat!, 'page-${p.contentId}')),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(widget.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: T.textPrimary)),
        if (p != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            placeCategoryTag(cat!),
            if (p.distLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(p.distLabel, style: const TextStyle(fontSize: 12.5, color: T.textMuted)),
            ],
          ]),
          if (p.addr.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.place_outlined, size: 14, color: T.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(p.addr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: T.textSecondary)),
              ),
            ]),
          ],
        ],
        if (s != null) ...[
          const SizedBox(height: 10),
          Text('글 ${s.posts} · 사진 ${s.photos} · 산책 ${s.walks}회',
              key: const Key('place-posts-summary'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textSecondary)),
        ],
      ]),
    );
  }

  Widget _tabs() => Row(children: [
        _tabChip(PlacePostsTab.photos, '사진', Icons.photo_library_outlined),
        const SizedBox(width: 8),
        _tabChip(PlacePostsTab.posts, '글', Icons.article_outlined),
      ]);

  Widget _tabChip(PlacePostsTab tab, String label, IconData icon) {
    final on = _tab == tab;
    return GestureDetector(
      key: Key('place-posts-tab-${tab.name}'),
      onTap: () => setState(() => _tab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: on ? const LinearGradient(colors: [T.warmStart, T.warmEnd]) : null,
          color: on ? null : T.surface,
          borderRadius: BorderRadius.circular(999),
          border: on ? null : Border.all(color: T.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: on ? Colors.white : T.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: on ? Colors.white : T.textSecondary)),
        ]),
      ),
    );
  }

  Widget _sortRow() => Row(children: [
        _sortChip(PlacePostsSort.latest, '최신'),
        const SizedBox(width: 6),
        _sortChip(PlacePostsSort.reactions, '반응 많은 순'),
      ]);

  Widget _sortChip(PlacePostsSort sort, String label) {
    final on = _sort == sort;
    return GestureDetector(
      key: Key('place-posts-sort-${sort.name}'),
      onTap: () => setState(() => _sort = sort),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: on ? T.accent : T.textMuted,
                decoration: on ? TextDecoration.underline : null)),
      ),
    );
  }

  /// 없다로 끝내지 않는다 — 첫 글의 문은 바닥 버튼이 늘 열어 둔다.
  Widget _emptyView({required bool photos}) => Padding(
        key: Key(photos ? 'place-posts-empty-photos' : 'place-posts-empty'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(children: [
          Icon(photos ? Icons.photo_library_outlined : Icons.edit_note_rounded, size: 36, color: T.textMuted),
          const SizedBox(height: 12),
          Text(photos ? '아직 이 장소의 사진이 없어요' : '아직 이 장소의 글이 없어요',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textSecondary)),
          const SizedBox(height: 6),
          Text(
              photos
                  ? '사진을 붙여 글을 쓰면 여기 사진 벽에 모여요'
                  : '${widget.title}에 다녀온 이야기를 첫 글로 남겨 주세요',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: T.textMuted)),
        ]),
      );

  Widget _failureView(CommunityFailure failure) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 34, color: T.textMuted),
            const SizedBox(height: 12),
            Text(failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.textSecondary)),
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
          ),
        ),
      );
}

// 아이 사진첩 — 이슈 #451 (5번).
//
// 커뮤니티 글에 "어떤 아이?" 로 이 아이를 고른 글이 모인다. 사진 있는 글은 사진 벽으로, 글만 있는 글은
// 한 줄씩(저장한 글 화면과 같은 모양). 서버가 `?dogId=` 로 좁혀 준다 — 글은 공개라 게스트도 볼 수 있지만
// 이 화면은 내 아이(내 정보)에서만 연다.
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/community_repository.dart';
import '../domain/date_label.dart';
import '../domain/pet.dart';
import '../theme/app_tokens.dart';
import '../widgets/aurora.dart';
import '../widgets/dog_avatar.dart';
import '../widgets/post_photo_wall.dart';
import 'post_detail_screen.dart';

class DogGalleryScreen extends StatefulWidget {
  final DogProfile dog;
  final CommunityRepository? repository;

  const DogGalleryScreen({super.key, required this.dog, this.repository});

  @override
  State<DogGalleryScreen> createState() => _DogGalleryScreenState();
}

class _DogGalleryScreenState extends State<DogGalleryScreen> {
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
    // 상세에서 저장 · 반응 · 댓글이 바뀌면 여기로 온다 — 어떻게 나왔든(#548).
    kCommunityRev.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    kCommunityRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // 토큰이 없으면 서버를 부르지 않는다 — 내 정보에서만 여는 화면이라 올 일이 없지만, 실제 저장소로
    // 여는 테스트(내 정보 메뉴)가 네트워크 타이머를 남기지 않게 저장한 글 화면과 같은 문을 둔다.
    // 게스트가 아니라 토큰으로 재는 것은 #673 이후의 공통 규칙이다.
    if (AuthState.hasNoToken) {
      setState(() {
        _loading = false;
        _failure = const CommunityFailure(CommunityFailureKind.unauthorized);
      });
      return;
    }
    final id = widget.dog.serverId;
    if (id == null) {
      // 서버에 없는 아이는 글에 붙은 적이 없다 — 부르지 않는다.
      setState(() {
        _loading = false;
        _posts = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final page = await _repo.feed(dogId: id, limit: 30);
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
    final id = widget.dog.serverId;
    if (cursor == null || id == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.feed(dogId: id, cursor: cursor, limit: 30);
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
    // 다시 읽기는 `kCommunityRev` 가 맡는다(#548) — 안드로이드 뒤로가기로 나오면 pop 결과가
    // 안 온다. 저장을 뺐는데 목록에 그대로 남는 것이 정확히 그 길이었다.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post, repository: _repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dog = widget.dog;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
              child: Row(children: [
                IconButton(
                  key: const Key('gallery-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: T.textPrimary),
                ),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [T.glowStart, T.glowEnd]),
                  ),
                  child: DogAvatar(dog: dog, size: 44, emojiSize: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${dog.name}의 사진첩',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900, color: T.textPrimary)),
                    const Text('커뮤니티에 올린 글 중 이 아이가 찍힌 것',
                        style: TextStyle(fontSize: 12, color: T.textMuted)),
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
        key: const Key('gallery-list'),
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
        key: Key('gallery-row-${post.id}'),
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

  Widget _emptyView() => Center(
        key: const Key('gallery-empty'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_library_outlined, size: 36, color: T.textMuted),
            const SizedBox(height: 12),
            Text('아직 ${widget.dog.name} 사진이 없어요',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.textSecondary)),
            const SizedBox(height: 6),
            Text('글쓰기에서 "어떤 아이?" 에 ${widget.dog.name}를 고르면 여기에 모여요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: T.textMuted)),
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
                key: const Key('gallery-retry'),
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
            key: const Key('gallery-more'),
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

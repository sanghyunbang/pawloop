// 홈의 "이웃의 사진" 한 줄 — 이슈 #451 (6번). 커뮤니티의 사진·영상 있는 글을 홈에서 한 줄로 보여
// 주고, 누르면 그 글로, "더 보기" 는 커뮤니티의 사진 벽으로 간다. 홈에서 커뮤니티로 가는 퍼널이다.
//
// ## 없으면 없다
//
// 사진 있는 글이 없거나 못 불러오면 **줄 자체가 없다.** 홈은 오늘의 산책이 주인공이고, 이 줄은
// 곁다리다 — 곁다리가 "불러오지 못했어요" 를 말하면 홈이 고장 난 것처럼 읽힌다(케어 카드·안전
// 지수 카드와 같은 판단).
//
// ## 첫 장 열두 개까지
//
// 목록 한 장(20개)에서 사진 있는 글의 첫 장만, 열두 개까지. 홈이 무거워지면 안 된다.
//
// ## 게스트에게는 없다
//
// 피드 자체는 공개지만, 홈의 곁다리 카드들(케어 · 오늘 할 일)과 같은 선을 지킨다 — 로그인해야
// 홈이 서버를 부른다. 로그인하면(상태가 바뀌면) 그때 받는다.
import 'package:flutter/material.dart';

import '../data/auth_state.dart';
import '../data/blocked_authors.dart';
import '../data/community_repository.dart';
import '../screens/post_detail_screen.dart';
import '../theme/app_tokens.dart';
import 'post_photo_wall.dart';

class NeighborPhotoStrip extends StatefulWidget {
  /// 테스트가 갈아 끼운다. 없으면 진짜를 만든다.
  final CommunityRepository? repository;

  /// 타일을 눌렀을 때. 없으면 글 상세를 민다.
  final ValueChanged<CommunityPost>? onOpen;

  /// "더 보기". 없으면 커뮤니티 탭을 사진 벽으로 연다 — 홈 화면이 정한다.
  final VoidCallback? onMore;

  static const int maxTiles = 12;

  const NeighborPhotoStrip({super.key, this.repository, this.onOpen, this.onMore});

  @override
  State<NeighborPhotoStrip> createState() => _NeighborPhotoStripState();
}

class _NeighborPhotoStripState extends State<NeighborPhotoStrip> {
  late final CommunityRepository _repo = widget.repository ?? CommunityRepository();
  List<CommunityPost> _posts = const [];

  @override
  void initState() {
    super.initState();
    AuthState.status.addListener(_load);
    // 차단하면 그 사람의 사진을 다시 부르지 않고 지금 줄에서 뺀다(애플 지침 1.2).
    BlockedAuthors.ids.addListener(_onBlocksChanged);
    _load();
  }

  @override
  void dispose() {
    AuthState.status.removeListener(_load);
    BlockedAuthors.ids.removeListener(_onBlocksChanged);
    super.dispose();
  }

  void _onBlocksChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    // 토큰이 없으면 안 부른다. 이 줄도 상태 알림을 듣고 다시 읽으므로, 게스트로만 재면
    // 소셜 버튼을 누른 순간(`authenticating`) 토큰 없는 요청이 나간다(#673).
    if (AuthState.hasNoToken) {
      if (mounted && _posts.isNotEmpty) setState(() => _posts = const []);
      return;
    }
    try {
      final page = await _repo.feed(limit: 20);
      if (!mounted) return;
      // 받아 둔 장은 그대로 두고, 그릴 때 차단한 사람의 사진을 뺀다 — 차단은 나중에도 일어난다.
      setState(() => _posts = PostPhotoWall.withMedia(page.items));
    } catch (_) {
      // 못 불러오면 줄이 없다 — 파일 머리말 참조.
      if (!mounted) return;
      setState(() => _posts = const []);
    }
  }

  void _open(CommunityPost post) {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen(post);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post, repository: _repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 홈의 이웃 사진도 커뮤니티 글 목록이다 — 차단한 사람의 사진은 안 건다(애플 지침 1.2).
    final tiles = visiblePosts(_posts).take(NeighborPhotoStrip.maxTiles).toList();
    if (tiles.isEmpty) return const SizedBox.shrink();
    // 위 여백은 줄이 있을 때만 — 없으면 홈에 빈 틈이 남는다.
    return Container(
      key: const Key('neighbor-photo-strip'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 14),
      decoration: BoxDecoration(
        color: T.cardBg,
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(color: T.cardBorder),
        boxShadow: T.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(children: [
            const Icon(Icons.photo_library_outlined, size: 16, color: T.warmText),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('이웃의 사진',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: T.textPrimary)),
            ),
            GestureDetector(
              key: const Key('photo-strip-more'),
              onTap: widget.onMore,
              behavior: HitTestBehavior.opaque,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('더 보기',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: T.warmText)),
                Icon(Icons.chevron_right, size: 16, color: T.warmText),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _tile(tiles[i]),
          ),
        ),
      ]),
    );
  }

  Widget _tile(CommunityPost post) {
    final media = post.media.first;
    final url = media.thumbnailUrl;
    return GestureDetector(
      key: Key('photo-strip-${post.id}'),
      onTap: () => _open(post),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(fit: StackFit.expand, children: [
            if (url == null)
              ColoredBox(color: T.surface)
            else
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(color: T.surface),
              ),
            if (media.kind.isVideo)
              const Center(
                child: Icon(Icons.play_circle_fill_rounded, size: 26, color: Colors.white),
              ),
          ]),
        ),
      ),
    );
  }
}

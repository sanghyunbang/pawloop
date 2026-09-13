// 사진 벽 — 이슈 #451 (1번). 사진·영상이 있는 글만 두 열 벽돌(masonry)로 깔아 한 화면에 여섯~
// 여덟 장이 보이게 한다. 핀터레스트 · 반려견 판의 격자 보기가 기준이다.
//
// ## 열을 나누는 규칙
//
// 카드를 순서대로 **더 짧은 열**에 붙인다. 열의 높이는 실제 픽셀이 아니라 "폭 1 기준 높이"
// (`1 / aspectRatio` + 글 한 줄)로 센다 — 그림이 오기 전에도 자리가 정해져야 하고, 두 열이
// 폭이 같으니 비율만으로 충분하다. 순서가 곧 정렬(최신순)이라, 왼쪽 위가 가장 새 글이다.
//
// ## 첫 장만 쓴다
//
// 글에 사진이 여럿이어도 벽에는 첫 장 하나다. 벽은 "구경하는 곳" 이고 나머지는 상세에서 본다.
// 비율은 [PostMedia.aspectRatio] 그대로라 4:5 … 1.91:1 로 잘린다(#440) — 세로 사진 하나가
// 열을 통째로 먹지 않는다.
import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../domain/date_label.dart';
import '../theme/app_tokens.dart';

class PostPhotoWall extends StatelessWidget {
  final List<CommunityPost> posts;
  final ValueChanged<CommunityPost> onTap;

  /// 테스트가 고정한다. 안 주면 기기 시계다.
  final DateTime? now;

  const PostPhotoWall({super.key, required this.posts, required this.onTap, this.now});

  /// 사진·영상이 있는 글만. 글만 있는 글은 벽에 없다 — 벽은 사진을 보는 곳이다.
  static List<CommunityPost> withMedia(List<CommunityPost> posts) =>
      posts.where((p) => p.media.isNotEmpty).toList();

  /// 폭 1 기준 한 장의 높이 — 그림 + 제목·작성자 두 줄.
  static double tileHeight(CommunityPost post) => 1 / post.media.first.aspectRatio + 0.28;

  /// 순서대로 더 짧은 열에 붙인다. 순수 함수라 따로 잰다.
  static List<List<CommunityPost>> split(List<CommunityPost> posts, {int columns = 2}) {
    final cols = List.generate(columns, (_) => <CommunityPost>[]);
    final heights = List.filled(columns, 0.0);
    for (final post in withMedia(posts)) {
      var shortest = 0;
      for (var i = 1; i < columns; i++) {
        if (heights[i] < heights[shortest] - 1e-9) shortest = i;
      }
      cols[shortest].add(post);
      heights[shortest] += tileHeight(post);
    }
    return cols;
  }

  @override
  Widget build(BuildContext context) {
    final columns = split(posts);
    return Row(
      key: const Key('post-photo-wall'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Column(children: [
              for (final post in columns[i]) ...[
                _PhotoTile(post: post, now: now, onTap: () => onTap(post)),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final CommunityPost post;
  final DateTime? now;
  final VoidCallback onTap;

  const _PhotoTile({required this.post, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final media = post.media.first;
    final url = media.thumbnailUrl;
    return GestureDetector(
      key: Key('photo-tile-${post.id}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: media.aspectRatio,
            child: Stack(fit: StackFit.expand, children: [
              if (url == null)
                const ColoredBox(color: Color(0xFF2B2440))
              else
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  // 못 불러오면 회색 칸 — 깨진 그림 아이콘을 벽에 띄우지 않는다.
                  errorBuilder: (_, __, ___) => ColoredBox(color: T.surface),
                ),
              if (media.kind.isVideo)
                const Center(
                  child: Icon(Icons.play_circle_fill_rounded, size: 34, color: Colors.white),
                ),
              if (post.media.length > 1)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('+${post.media.length - 1}',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(post.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: T.textPrimary)),
        const SizedBox(height: 2),
        Text('${post.author.nickname} · ${dateLabel(post.createdAt, now: now)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: T.textMuted)),
      ]),
    );
  }
}

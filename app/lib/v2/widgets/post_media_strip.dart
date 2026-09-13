// 글에 붙은 사진·영상을 카드와 상세에 그린다 — 이슈 #429.
//
// ## 한 장이면 크게, 여럿이면 격자
//
// 한 장은 카드 폭을 다 쓰고 서버가 준 크기로 자리를 **미리** 잡는다(`aspectRatio`) — 사진이
// 도착할 때 카드가 뛰지 않는다. 두 장은 나란히, 셋 이상은 2×2 격자에 넷까지 그리고 다섯째부터는
// 넷째 칸 위에 `+N` 을 쓴다. 목록 응답 하나에 URL 열 개가 실려도 그림은 넷만 받는다.
//
// ## 영상은 썸네일과 재생 표시만
//
// 피드에서 자동재생하지 않는다 — 데이터와 배터리다. 누르면 전체 보기로 간다. 재생 자체는
// 영상 PR 의 일이고, 그전까지 전체 보기는 썸네일과 안내 한 줄이다.
import 'package:flutter/material.dart';

import '../domain/post_media.dart';
import 'post_media_viewer.dart';

class PostMediaStrip extends StatelessWidget {
  final List<PostMedia> media;

  const PostMediaStrip({super.key, required this.media});

  /// 격자에 실제로 그리는 수. 나머지는 `+N` 이다.
  static const int maxTiles = 4;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();

    final Widget body;
    if (media.length == 1) {
      body = AspectRatio(
        aspectRatio: media.single.aspectRatio,
        child: _Tile(media: media.single, onTap: () => _open(context, 0)),
      );
    } else if (media.length == 2) {
      body = AspectRatio(
        aspectRatio: 2,
        child: Row(children: [
          Expanded(child: _Tile(media: media[0], onTap: () => _open(context, 0))),
          const SizedBox(width: 4),
          Expanded(child: _Tile(media: media[1], onTap: () => _open(context, 1))),
        ]),
      );
    } else {
      final shown = media.take(maxTiles).toList();
      final hidden = media.length - shown.length;
      body = GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < shown.length; i++)
            _Tile(
              media: shown[i],
              onTap: () => _open(context, i),
              // 다섯째부터는 넷째 칸이 "+N" 을 든다 — 누르면 전체 보기의 그 자리로 간다.
              overflow: i == shown.length - 1 && hidden > 0 ? hidden : 0,
            ),
        ],
      );
    }

    return ClipRRect(
      key: const Key('post-media-strip'),
      borderRadius: BorderRadius.circular(14),
      child: body,
    );
  }

  void _open(BuildContext context, int index) =>
      PostMediaViewer.open(context, media, initialIndex: index);
}

class _Tile extends StatelessWidget {
  final PostMedia media;
  final VoidCallback onTap;

  /// 0 보다 크면 이 칸 위에 `+N` 을 쓴다.
  final int overflow;

  const _Tile({required this.media, required this.onTap, this.overflow = 0});

  @override
  Widget build(BuildContext context) {
    final url = media.thumbnailUrl;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(fit: StackFit.expand, children: [
        if (url == null)
          const ColoredBox(color: Color(0xFF2B2440))
        else
          Image.network(
            url,
            fit: BoxFit.cover,
            // 못 불러오면 회색 칸 — 깨진 그림 아이콘을 카드에 띄우지 않는다.
            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x22000000)),
          ),
        if (media.kind.isVideo)
          const Center(
            child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white),
          ),
        if (overflow > 0)
          ColoredBox(
            color: const Color(0x8C000000),
            child: Center(
              child: Text('+$overflow',
                  key: const Key('post-media-overflow'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

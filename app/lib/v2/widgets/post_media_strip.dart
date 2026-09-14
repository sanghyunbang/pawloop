// 글에 붙은 사진·영상 — 이슈 #429 · #465.
//
// ## 한 장은 크게, 여러 장은 캐러셀
//
// 한 장은 카드 폭을 다 쓰고 서버가 준 크기로 자리를 **미리** 잡는다(`aspectRatio`) — 사진이
// 오기 전에 카드가 뛰지 않는다. 둘 이상이면 **옆으로 넘기는 캐러셀**이다(Instagram · Material 3):
// 첫 장의 비율을 전부가 따르고, 오른쪽 위에 "1/N", 아래에 점. 예전의 2×2 격자는 사진이 카드
// 폭의 절반이라 무엇이 찍혔는지 안 보였다(#465).
//
// ## 목록에서는 정사각까지
//
// [minAspect] 가 세로 사진을 어디까지 두는지 정한다. 카드는 1(정사각)까지 — 세로 사진 하나가
// 화면 절반을 먹으면 한 화면에 글이 하나뿐이다(#465, Reddit 의 카드). 상세는 4:5 까지(기본값,
// #440). 원본은 전체 보기에서 본다.
import 'package:flutter/material.dart';

import '../domain/post_media.dart';
import 'post_media_viewer.dart';

class PostMediaStrip extends StatelessWidget {
  final List<PostMedia> media;

  /// 세로 사진의 하한 비율. 카드는 `1`, 상세·벽은 [PostMedia.minFeedAspectRatio](4:5).
  final double minAspect;

  /// 두 번 탭 — 카드가 귀여워요를 남기는 데 쓴다(#451 4번). 안 주면 두 번 탭 인식기가 없어
  /// 한 번 탭이 늦어지지 않는다(상세 · 벽).
  final VoidCallback? onDoubleTap;

  const PostMediaStrip({
    super.key,
    required this.media,
    this.minAspect = PostMedia.minFeedAspectRatio,
    this.onDoubleTap,
  });

  /// 첫 장의 비율. [minAspect] 보다 세로로 길면 거기서 자른다.
  double get aspect {
    final a = media.first.aspectRatio;
    return a < minAspect ? minAspect : a;
  }

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      key: const Key('post-media-strip'),
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: aspect,
        child: media.length == 1
            ? _Tile(media: media.single, onTap: () => _open(context, 0), onDoubleTap: onDoubleTap)
            : _Carousel(media: media, onOpen: (i) => _open(context, i), onDoubleTap: onDoubleTap),
      ),
    );
  }

  void _open(BuildContext context, int index) =>
      PostMediaViewer.open(context, media, initialIndex: index);
}

/// 옆으로 넘기는 여러 장. 자동으로 넘기지 않는다.
class _Carousel extends StatefulWidget {
  final List<PostMedia> media;
  final ValueChanged<int> onOpen;
  final VoidCallback? onDoubleTap;

  const _Carousel({required this.media, required this.onOpen, this.onDoubleTap});

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final n = widget.media.length;
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        key: const Key('post-media-carousel'),
        itemCount: n,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) =>
            _Tile(media: widget.media[i], onTap: () => widget.onOpen(i), onDoubleTap: widget.onDoubleTap),
      ),
      // "1/N" — 사진이 여럿이라는 것을 첫눈에 알 수 있게(Instagram).
      Positioned(
        top: 8,
        right: 8,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xB3000000),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${_index + 1}/$n',
                key: const Key('post-media-counter'),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 8,
        child: IgnorePointer(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _index ? Colors.white : const Color(0x80FFFFFF),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final PostMedia media;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _Tile({required this.media, required this.onTap, this.onDoubleTap});

  @override
  Widget build(BuildContext context) {
    final url = media.thumbnailUrl;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
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
        // 길이는 재생 전에 알 수 있는 유일한 사실이다 — 60초짜리인지 5초짜리인지.
        if (media.durationLabel case final label?)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xB3000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  key: const Key('post-media-duration'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

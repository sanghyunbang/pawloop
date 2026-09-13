// 사진·영상 전체 보기 — 이슈 #429.
//
// 화면 파일이 아니라 위젯인 이유: 전체 화면 대화상자다. 라우터에 길이 없고 `showDialog` 로
// 띄운다 — 만들기 시트·고르기 시트가 `widgets/` 에 사는 것과 같은 판단이다.
//
// 영상 재생은 영상 PR 의 일이다. 그전까지 영상 칸은 썸네일과 안내 한 줄이다 — 재생 버튼이
// 아무 일도 안 하는 것보다 "곧" 이라고 말하는 편이 낫다.
import 'package:flutter/material.dart';

import '../domain/post_media.dart';

class PostMediaViewer extends StatefulWidget {
  final List<PostMedia> media;
  final int initialIndex;

  const PostMediaViewer({super.key, required this.media, this.initialIndex = 0});

  static Future<void> open(BuildContext context, List<PostMedia> media,
      {int initialIndex = 0}) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: PostMediaViewer(media: media, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<PostMediaViewer> createState() => _PostMediaViewerState();
}

class _PostMediaViewerState extends State<PostMediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      PageView.builder(
        key: const Key('post-media-viewer'),
        controller: _pages,
        itemCount: widget.media.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _page(widget.media[i]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            IconButton(
              key: const Key('post-media-viewer-close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
            const Spacer(),
            Text('${_index + 1} / ${widget.media.length}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
          ]),
        ),
      ),
    ]);
  }

  Widget _page(PostMedia media) {
    if (media.kind.isVideo) {
      return Stack(fit: StackFit.expand, children: [
        if (media.posterUrl case final poster?)
          Image.network(poster, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        const Center(
          child: Text('영상 재생은 곧 지원돼요',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ]);
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.network(
          media.url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
              size: 48, color: Colors.white38),
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(color: Colors.white54)),
        ),
      ),
    );
  }
}

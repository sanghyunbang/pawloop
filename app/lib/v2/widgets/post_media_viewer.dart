// 사진·영상 전체 보기 — 이슈 #429.
//
// 화면 파일이 아니라 위젯인 이유: 전체 화면 대화상자다. 라우터에 길이 없고 `showDialog` 로
// 띄운다 — 만들기 시트·고르기 시트가 `widgets/` 에 사는 것과 같은 판단이다.
//
// ## 영상은 눌러야 돈다
//
// 페이지에 들어오자마자 재생하지 않는다 — 포스터와 재생 버튼으로 시작하고, 누르면 그때
// `video_player` 컨트롤러를 만든다. 데이터와 배터리이고, 넘겨 보다 스친 영상이 소리를 내지
// 않는다. 컨트롤러는 페이지가 내려갈 때 버린다.
//
// 컨트롤러를 만드는 함수를 밖에서 꽂을 수 있다 — 위젯 테스트에는 플레이어 플랫폼이 없어서,
// "누르기 전엔 안 만든다" 와 "못 만들면 안내 한 줄" 을 그 자리로 잰다.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/post_media.dart';

/// 재생 컨트롤러를 만드는 자리. 기본은 네트워크 URL 이다.
typedef VideoControllerFactory = VideoPlayerController Function(Uri url);

class PostMediaViewer extends StatefulWidget {
  final List<PostMedia> media;
  final int initialIndex;
  final VideoControllerFactory controllerFactory;

  const PostMediaViewer({
    super.key,
    required this.media,
    this.initialIndex = 0,
    this.controllerFactory = VideoPlayerController.networkUrl,
  });

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
      return _VideoPage(
        key: ValueKey('post-media-video-${media.id}'),
        media: media,
        controllerFactory: widget.controllerFactory,
      );
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

/// 영상 한 페이지 — 포스터 · 재생 버튼, 누르면 플레이어.
class _VideoPage extends StatefulWidget {
  final PostMedia media;
  final VideoControllerFactory controllerFactory;

  const _VideoPage({super.key, required this.media, required this.controllerFactory});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    VideoPlayerController? controller;
    try {
      controller = widget.controllerFactory(Uri.parse(widget.media.url));
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
    } catch (_) {
      // 플레이어가 못 뜨는 이유(코덱 · 네트워크 · 플랫폼)를 사용자가 고칠 수는 없다 — 한 줄이면 된다.
      controller?.dispose();
      controller = null;
      if (mounted) setState(() => _error = '재생할 수 없어요');
    }
    if (!mounted) {
      controller?.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _starting = false;
    });
    controller?.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) {
      _start();
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Stack(fit: StackFit.expand, children: [
        if (ready)
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          )
        else if (widget.media.posterUrl case final poster?)
          Image.network(poster, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        if (_starting)
          const Center(child: CircularProgressIndicator(color: Colors.white54))
        else if (!ready || !controller.value.isPlaying)
          Center(
            child: Icon(Icons.play_circle_fill_rounded,
                key: const Key('post-media-play'), size: 64, color: Colors.white),
          ),
        if (ready)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                  playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
            ),
          ),
        if (_error case final error?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(error,
                key: const Key('post-media-video-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
      ]),
    );
  }
}

// 두 번 탭 하트 — 이슈 #451 (4번).
//
// 사진을 두 번 탭하면 하트가 사진 한가운데서 커졌다가 사라진다(Instagram). 서버 응답을 기다리지
// 않고 **즉시** 뜬다 — 손가락에 대한 대답이지 집계가 아니다. 집계(수 · 채운 하트)는 응답이 와야
// 바뀐다(상세와 같은 규칙, 낙관적 갱신 없음).
//
// [trigger] 가 바뀔 때마다 한 번 튄다. 부모가 글마다 수를 하나 들고 두 번 탭할 때 올린다.
import 'package:flutter/material.dart';

class LikeBurst extends StatefulWidget {
  final int trigger;

  const LikeBurst({super.key, required this.trigger});

  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 25),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
  ]).animate(_controller);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
  ]).animate(_controller);

  @override
  void didUpdateWidget(LikeBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          if (!_controller.isAnimating) return const SizedBox.shrink();
          return Center(
            child: Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: const Icon(
                  Icons.favorite_rounded,
                  key: Key('like-burst'),
                  size: 96,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 18)],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

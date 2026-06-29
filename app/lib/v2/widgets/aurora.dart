import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/emotions.dart';
import '../theme/themes.dart';

/// 라일락 베이스 + 은은한 오라 블롭 배경.
/// 전역 [AppThemeCtl]를 구독 → 배경 테마 변경 시 앱 전체에 반영.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final Emotion? tint;
  const AuroraBackground({super.key, required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeCtl.index,
      builder: (_, ti, __) {
        final th = kThemes[ti];
        final e = tint;
        if (e != null) {
          // 감정 화면: 감정색이 오브(중앙 상단)에서 화면 전체로 번지는 배경.
          return Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(Colors.white, e.c1, 0.14)!,
                      Color.lerp(th.baseBottom, e.c2, 0.20)!,
                    ],
                  ),
                ),
              ),
            ),
            _glow(const Alignment(0.0, -0.34), 1.05, e.c1, 0.55), // 오브 글로우(핵심)
            _glow(const Alignment(-0.95, -1.0), 0.95, e.c1, 0.40), // 상단 좌
            _glow(const Alignment(1.0, -0.75), 0.90, e.c2, 0.38), // 상단 우
            _glow(const Alignment(0.0, 1.2), 1.10, e.c2, 0.30), // 하단
            child,
          ]);
        }
        // 비감정 화면: 테마 오로라(은은하지만 또렷하게 퍼지도록).
        return Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [th.baseTop, th.baseBottom],
                ),
              ),
            ),
          ),
          _glow(const Alignment(-0.9, -0.95), 0.95, th.blob1, 0.50),
          _glow(const Alignment(1.0, -0.8), 0.90, th.blob2, 0.42),
          _glow(const Alignment(0.0, 1.2), 1.10, th.blob3, 0.40),
          child,
        ]);
      },
    );
  }

  /// 화면 전체를 채우는 부드러운 방사형 글로우.
  Widget _glow(Alignment center, double radius, Color color, double opacity) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
            stops: const [0.0, 0.78],
          ),
        ),
      ),
    );
  }
}

/// 글래스 카드.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = T.radius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0x73FFFFFF),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x99FFFFFF)),
            boxShadow: T.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 천천히 위아래로 떠다니는 광택 감정 오브.
class FloatingOrb extends StatefulWidget {
  final Emotion emotion;
  final double size;
  const FloatingOrb({super.key, required this.emotion, this.size = 184});

  @override
  State<FloatingOrb> createState() => _FloatingOrbState();
}

class _FloatingOrbState extends State<FloatingOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.emotion;
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final dy = math.sin(_c.value * 2 * math.pi) * 9; // ±9px 부유
        return SizedBox(
          width: s,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 바깥 발광
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [e.c1.withOpacity(0.45), e.c1.withOpacity(0)],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, dy),
                child: Container(
                  width: s * 0.74,
                  height: s * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.45),
                      radius: 1.1,
                      colors: [
                        Color.lerp(e.c1, Colors.white, 0.45)!,
                        e.c1,
                        e.c2,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(color: e.c2.withOpacity(0.40), blurRadius: 34, offset: const Offset(0, 16)),
                    ],
                  ),
                  child: Align(
                    alignment: const Alignment(-0.45, -0.55),
                    child: Container(
                      width: s * 0.2,
                      height: s * 0.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Colors.white.withOpacity(0.7), Colors.white.withOpacity(0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

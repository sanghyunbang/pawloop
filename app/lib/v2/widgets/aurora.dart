import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/themes.dart';

/// 라일락 베이스 + 은은한 오라 블롭 배경.
/// 전역 [AppThemeCtl]를 구독 → 배경 테마 변경 시 앱 전체에 반영.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppThemeCtl.index,
      builder: (_, ti, __) {
        final th = kThemes[ti];
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
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
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
            color: const Color(0xD6FFFFFF),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xCCFFFFFF)),
            boxShadow: T.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

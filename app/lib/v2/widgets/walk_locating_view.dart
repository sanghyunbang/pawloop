// lib/v2/widgets/walk_locating_view.dart
//
// 산책 시작 직후, 첫 위치를 판정하는 동안의 화면.
//
// 예전엔 보라 화면에 스피너 하나였다 — 3초쯤 아무 말이 없어서 "멈췄나" 로 읽혔다(#327).
// 기다리는 이유와 빨라지는 조건을 한 줄씩 말한다.
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class WalkLocatingView extends StatelessWidget {
  const WalkLocatingView({super.key});

  static const String title = '위치를 잡는 중이에요';
  static const String hint = '하늘이 보이는 곳이면 빨라요';

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: T.bgTop,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
              SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: T.textPrimary),
              ),
              SizedBox(height: 6),
              Text(hint, style: TextStyle(fontSize: 12.5, color: T.textMuted)),
            ],
          ),
        ),
      );
}

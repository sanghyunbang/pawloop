import 'package:flutter/material.dart';

/// 디자인 토큰 (design_refactor 핸드오프 인라인 스타일에서 추출).
/// 기본 테마 = '라일락'.
class T {
  T._();

  // 텍스트
  static const textPrimary = Color(0xFF2C2740);
  static const textSecondary = Color(0xFF574F6E);
  static const textMuted = Color(0xFF9B93B3);
  static const textFaint = Color(0xFFBBB3CC);

  // 글래스 카드 (var(--cbg)/--cbd/--cr 근사)
  static const cardBg = Color(0xC6FFFFFF); // white ~0.78
  static const cardBorder = Color(0x80FFFFFF);
  static const double radius = 22;

  // 라일락 베이스 배경 (linear-gradient 180deg)
  static const lilacTop = Color(0xFFF3E8F9);
  static const lilacBottom = Color(0xFFE4D6F0);

  // 라일락 오라 블롭 (radial-gradient stops)
  static const auroraPeach = Color(0xFFFFC79E);
  static const auroraLilac = Color(0xFFD4B0FF);
  static const auroraMint = Color(0xFF9EE2C4);

  // 시그니처 그라데이션 (SIG: 140deg #FF9E7D → #D89BFF)
  static const sigStart = Color(0xFFFF9E7D);
  static const sigEnd = Color(0xFFD89BFF);
  static const LinearGradient sig = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [sigStart, sigEnd],
  );

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x1A5A4682), blurRadius: 26, offset: Offset(0, 10)),
  ];
}

import 'package:flutter/material.dart';

/// 배경 테마 (핸드오프 THEMES). base 상하 그라데이션 + 3개 오라 blob 색.
class AppThemeDef {
  final String name;
  final Color baseTop;
  final Color baseBottom;
  final Color blob1; // 좌상
  final Color blob2; // 우상
  final Color blob3; // 중하
  const AppThemeDef(this.name, this.baseTop, this.baseBottom, this.blob1, this.blob2, this.blob3);

  /// 스와치/미리보기 145deg 그라데이션.
  LinearGradient get swatch => LinearGradient(
        begin: const Alignment(-0.7, -1),
        end: const Alignment(0.7, 1),
        colors: [blob1, blob2, blob3],
        stops: const [0.0, 0.55, 1.0],
      );
}

const List<AppThemeDef> kThemes = [
  AppThemeDef('라일락', Color(0xFFF3E8F9), Color(0xFFE4D6F0), Color(0xFFFFC79E), Color(0xFFD4B0FF), Color(0xFF9EE2C4)),
  AppThemeDef('블루', Color(0xFFE8EFFA), Color(0xFFDBE3F4), Color(0xFF9EC3FF), Color(0xFFA8B6FF), Color(0xFF9FE0E6)),
  AppThemeDef('민트', Color(0xFFE6F3EC), Color(0xFFD6EAE1), Color(0xFF9DE9C9), Color(0xFFA8DCF2), Color(0xFFDCE9A6)),
  AppThemeDef('코랄', Color(0xFFFBE9E4), Color(0xFFF4DBDD), Color(0xFFFFB892), Color(0xFFFF9FBE), Color(0xFFFFD79A)),
  AppThemeDef('모노', Color(0xFFEEEFF4), Color(0xFFE2E2EC), Color(0xFFC7CCDC), Color(0xFFD5CBE4), Color(0xFFCDE0D9)),
];

/// 프로필 테두리 색 후보.
const List<Color> kAvatarBorders = [
  Color(0xFF8E7BFF), // 라일락
  Color(0xFFFF7A59), // 코랄
  Color(0xFF33BFA6), // 민트
  Color(0xFF5B79F5), // 블루
  Color(0xFFFF6B9D), // 핑크
  Color(0xFFFFC44D), // 옐로
];

/// 현재 배경 테마 인덱스 + 프로필 테두리 색 (전역). 위젯들이 구독해 앱 전체에 반영.
class AppThemeCtl {
  static final ValueNotifier<int> index = ValueNotifier<int>(0);
  static AppThemeDef get current => kThemes[index.value];

  /// 프로필 아바타 테두리 색.
  static final ValueNotifier<Color> avatarBorder = ValueNotifier<Color>(const Color(0xFF8E7BFF));
}

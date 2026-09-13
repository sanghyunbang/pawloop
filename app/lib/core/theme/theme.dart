import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:heat_trip_flutter/v2/theme/app_tokens.dart';

AppBarTheme appBarTheme() {
  return AppBarTheme(
    centerTitle: false,
    backgroundColor: Colors.white,
    elevation: 0.0,
    scrolledUnderElevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: GoogleFonts.nanumGothic(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    ),
  );
}

BottomNavigationBarThemeData bottomNavigationTheme() {
  return const BottomNavigationBarThemeData(
    selectedItemColor: Color(0xFFEB9C64),
    unselectedItemColor: Colors.grey,
    showUnselectedLabels: true,
  );
}

ThemeData theme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pretendard',
    // 머티리얼 위젯(날짜·시각 고르기, 대화상자, 기본 FilledButton)의 색 — #445.
    // colorScheme 이 없으면 머티리얼 3 기본 보라(#6750A4)로 그려져 앱의 피치·라일락과 어긋난다.
    // 시드는 플로팅 네비의 활성색이자 아바타 테두리 기본값인 accent(#8E7BFF)다. sigEnd(#D89BFF)를
    // primary 로 쓰면 흰 글자가 안 읽혀서 한 단계 진한 accent 를 primary 로 둔다.
    colorScheme: ColorScheme.fromSeed(seedColor: T.accent).copyWith(
      primary: T.accent,
      onPrimary: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
    shadowColor: Colors.transparent,

    appBarTheme: appBarTheme(),
    bottomNavigationBarTheme: bottomNavigationTheme(),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    cardTheme: const CardThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    dialogTheme: const DialogThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    // 전역 스낵바: floating + 하단 여백 + 둥근 모서리
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      insetPadding: EdgeInsets.fromLTRB(12, 0, 12,5),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    chipTheme: const ChipThemeData(
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
    ),

    bottomAppBarTheme: const BottomAppBarThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
  );
}

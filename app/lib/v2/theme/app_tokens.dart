import 'package:flutter/material.dart';

/// 디자인 토큰 — `docs/01-design/design-system.md` §2 · §7 의 코드 쪽.
///
/// ## 색은 여기서만 정한다 (#447)
///
/// 2026-09-13 까지 브랜드 색이 화면마다 인라인 `Color(0x…)` 로 적혀 있었다 — 166곳, 26파일.
/// 주황 글자 `#E07A4E` 만 75곳이었다. 그 상태에서는 팔레트를 바꾸려 해도 토큰 값만 바뀌고
/// 화면의 절반은 예전 색으로 남는다. 그래서 값은 그대로 두고 **이름부터** 여기로 모았다.
/// 팔레트를 바꾸는 날은 이 파일의 값만 바꾸면 된다(#447 에서 사장님이 고르시는 중).
///
/// 이름은 **역할**이다.
///
///   * [accent] — 활성 탭 · 선택 · 링크 (라일락 `#8E7BFF`)
///   * [sig] — 시그니처 그라데이션 (피치→라일락). 탭 바 산책 버튼 · 아바타 테두리
///   * [warm] — 따뜻한 그라데이션 (살구→코랄). 홈 CTA · 채움 버튼
///   * [warmText] · [warmMid] — 주황 글자와 주황 테두리. "더보기" · 선택된 칩
///   * 카테고리색(지도)과 상태색(빨강 오류 · 초록 성공 · 앰버 주의)은 토큰이 아니라 그대로다.
class T {
  T._();

  // ── 글자 4단계
  static const textPrimary = Color(0xFF2C2740);
  static const textSecondary = Color(0xFF574F6E);
  static const textMuted = Color(0xFF9B93B3);
  static const textFaint = Color(0xFFBBB3CC);

  // ── 글래스 카드 표면 (var(--cbg)/--cbd/--cr 근사)
  static const cardBg = Color(0xC6FFFFFF); // white ~0.78
  static const cardBorder = Color(0x80FFFFFF);
  static const double radius = 22;

  /// 카드보다 한 톤 밝은 면 — 목록 줄 · 입력칸 바탕.
  static const surface = Color(0xFFF1ECF7);
  static const surfaceBright = Color(0xFFFCFAFF);

  /// 옅은 선 — 입력칸 · 카드 안 구분선 (라일락 12%).
  static const line = Color(0x1F8C7BFF);

  // ── 바탕 (linear-gradient 180deg). 기본 테마(`kThemes[0]`)와 같은 값.
  static const bgTop = Color(0xFFF3E8F9);
  static const bgBottom = Color(0xFFE4D6F0);

  // ── 오라 블롭 (radial-gradient stops)
  static const auroraPeach = Color(0xFFFFC79E);
  static const auroraLilac = Color(0xFFD4B0FF);
  static const auroraMint = Color(0xFF9EE2C4);

  /// 아이 히어로 · 로그인 로고 뒤의 둥근 빛 (살구).
  static const glowStart = Color(0xFFFFE7D2);
  static const glowEnd = Color(0xFFFFD0C0);

  // ── 강조색 — 플로팅 네비의 활성 탭 · 아바타 테두리 기본값 · 머티리얼 primary (#445)
  static const accent = Color(0xFF8E7BFF);

  /// 강조색 8% — 알약 바탕
  static const accentSoft = Color(0x148C7BFF);

  /// 강조색 20% — 선택된 테두리 · 조금 진한 바탕
  static const accentLine = Color(0x338C7BFF);

  // ── 시그니처 그라데이션 (SIG: 140deg #FF9E7D → #D89BFF)
  static const sigStart = Color(0xFFFF9E7D);
  static const sigEnd = Color(0xFFD89BFF);
  static const LinearGradient sig = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [sigStart, sigEnd],
  );

  /// SIG 버튼 밑 그림자 (라일락 30%)
  static const sigGlow = Color(0x4DD89BFF);

  // ── 따뜻한 그라데이션 (홈 CTA · 채움 버튼: 140deg #FFA96B → #FF7E8A)
  static const warmStart = Color(0xFFFFA96B);
  static const warmEnd = Color(0xFFFF7E8A);
  static const LinearGradient warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [warmStart, warmEnd],
  );

  /// 따뜻한 버튼 밑 그림자 (코랄 40%)
  static const warmGlow = Color(0x66FF7E8A);

  /// 주황 글자 — "더보기" · 링크 · 선택된 칩 글자. 흰 바탕에서 읽히는 진한 쪽.
  static const warmText = Color(0xFFE07A4E);

  /// 주황 테두리·점 — 선택된 칩 테두리 · 케어 색
  static const warmMid = Color(0xFFFF8F63);

  /// 따뜻한 칩 바탕 (코랄 10%)
  static const warmSoft = Color(0x1AFF7E8A);

  // ── 그림자
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x1A5A4682), blurRadius: 26, offset: Offset(0, 10)),
  ];

  /// 떠 있는 탭 바 밑 그림자
  static const barShadow = Color(0x2E5A4690);
}

import 'package:flutter/material.dart';

/// 디자인 토큰 — `docs/01-design/design-system.md` §2 · §7 의 코드 쪽.
///
/// ## 흰 바탕, 색은 버튼과 외곽선에 (#447)
///
/// 2026-09-14 결정: "배경은 시각적 부담 없는 흰색으로 하고, 버튼이든 외곽선에 색을 주는
/// 것으로." 그 전 라일락 바탕 + 피치→라일락 그라데이션은 핑크 위주라 부담스럽다고 했고, 제가
/// 낸 단색(틸·파랑·초록) 후보는 전부 기각됐다. 그래서:
///
///   * 바탕은 **흰색**. 카드는 흰색에 옅은 **외곽선**([cardBorder]) 으로 구분한다 — 반투명이
///     아니라 선이 카드를 만든다.
///   * 색은 **버튼과 선택에만**: 채움 버튼은 [warm](살구→코랄, 핑크 없음), 활성 탭·선택된 칩·
///     선택된 날·링크는 [accent](코랄) 하나.
///   * 글자는 웜 차콜 4단계. 카테고리색(지도)과 상태색(빨강 오류 · 초록 성공 · 앰버 주의)은
///     토큰이 아니라 그대로다.
///
/// 색은 여기서만 정한다 — 화면에 인라인 `Color(0x…)` 로 브랜드 색을 적지 않는다(351곳을 모았다).
/// 라일락 등 오라 테마는 `themes.dart` 의 고르기 옵션으로 남아 있고 기본은 '화이트' 다.
class T {
  T._();

  // ── 글자 — 웜 차콜 4단계
  static const textPrimary = Color(0xFF2B2825);
  static const textSecondary = Color(0xFF5A544D);
  static const textMuted = Color(0xFF9A938A);
  static const textFaint = Color(0xFFC2BBB1);

  // ── 카드 — 흰색 + 외곽선. 흰 바탕 위라 선이 없으면 카드가 안 보인다.
  static const cardBg = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFECE8E2);
  static const double radius = 22;

  /// 카드보다 한 톤 가라앉은 면 — 목록 줄 · 칩 바탕 · 비활성 상자.
  static const surface = Color(0xFFF7F5F2);
  static const surfaceBright = Color(0xFFFFFFFF);

  /// 옅은 선 — 입력칸 · 구분선. 카드 외곽선보다 살짝 진하다.
  static const line = Color(0xFFE4E0DA);

  // ── 바탕 — 흰색. 기본 테마(`kThemes[0]` '화이트')와 같은 값.
  static const bgTop = Color(0xFFFFFFFF);
  static const bgBottom = Color(0xFFFFFFFF);

  // ── 오라 블롭 — 인트로 카드의 색조 등에 남아 있다. 기본 테마에서는 안 그린다.
  static const auroraPeach = Color(0xFFFFC79E);
  static const auroraLilac = Color(0xFFBFD8F5);
  static const auroraMint = Color(0xFF9EE2C4);

  /// 아이 히어로 · 로그인 로고 뒤의 둥근 빛 (살구). 흰 바탕 위의 유일한 넓은 색면이다.
  static const glowStart = Color(0xFFFFE7D2);
  static const glowEnd = Color(0xFFFFD0C0);

  // ── 강조색 하나 — 코랄레드. 활성 탭 · 선택된 칩 · 선택된 날 · 링크 · 머티리얼 primary.
  // 흰 글자가 4:1 로 읽히는 밝기다(#F0603F 는 3.3:1 이라 한 톤 내렸다 — app_tokens_test).
  static const accent = Color(0xFFE04A2B);

  /// 강조색 8% — 알약 바탕
  static const accentSoft = Color(0x14E04A2B);

  /// 강조색 20% — 선택된 테두리 · 조금 진한 바탕
  static const accentLine = Color(0x33E04A2B);

  // ── 시그니처 그라데이션 (피치 → 코랄레드): 아바타 테두리 · 머리말의 둥근 버튼
  static const sigStart = Color(0xFFFF9E7D);
  static const sigEnd = Color(0xFFE04A2B);
  static const LinearGradient sig = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [sigStart, sigEnd],
  );

  /// SIG 버튼 밑 그림자
  static const sigGlow = Color(0x40E04A2B);

  // ── 따뜻한 그라데이션 (주황 → 코랄레드): 홈 CTA · 채움 버튼. 중간색 위 흰 글자 3:1.
  static const warmStart = Color(0xFFFF8F4D);
  static const warmEnd = Color(0xFFE04A2B);
  static const LinearGradient warm = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
    colors: [warmStart, warmEnd],
  );

  /// 따뜻한 버튼 밑 그림자
  static const warmGlow = Color(0x40E04A2B);

  /// 주황 글자 — "더보기" · 링크 · 선택된 칩 글자. 흰 바탕에서 읽히는 진한 쪽.
  static const warmText = Color(0xFFE07A4E);

  /// 주황 테두리·점 — 선택된 칩 테두리 · 케어 색
  static const warmMid = Color(0xFFFF8F63);

  /// 따뜻한 칩 바탕 (코랄 10%)
  static const warmSoft = Color(0x1AE04A2B);

  // ── 그림자 — 흰 바탕이라 아주 옅게. 카드는 선이 만들고 그림자는 거든다.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0F3A342E), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// 떠 있는 탭 바 밑 그림자
  static const barShadow = Color(0x1F3A342E);
}

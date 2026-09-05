/**
 * 약관 동의의 기록 — 이슈 #190.
 *
 * <h2>이 모듈이 아는 것</h2>
 * <p>"어느 계정이 어느 문서의 어느 버전에 언제 동의(또는 철회)했는가" 만 안다. 문서의
 * 내용도, 지금 버전이 몇인지도 모른다 — 문서는 앱이 들고 있고({@code app/assets/terms/}),
 * 재동의가 필요한지도 앱이 자기가 든 버전과 여기 기록을 견줘서 정한다. 서버가 버전을
 * 알게 하면 앱의 문서와 조용히 갈린다.
 *
 * <h2>{@code users} 의 아홉 컬럼은 지웠다</h2>
 * <p>{@code users} 에 {@code agree_tos}·{@code tos_version}·{@code tos_agreed_at} 같은
 * 컬럼이 아홉 개 있었다. 이메일 가입 경로만 채우고 소셜 가입은 안 채웠다. 그리고 <b>덮어쓰는
 * 칸이라 이력이 없었다</b> — 철회하면 "언제까지 동의 상태였는지" 가 사라지고, 버전을 올리면
 * 이전 버전에 동의했던 사실이 사라진다. 위치정보법 제24조는 철회 <b>전</b>에 제공된 것은
 * 그대로라고 하므로 그 경계 시각이 남아야 한다. 그래서 이 표는 <b>덧붙이기만 하는 이력 표</b>고,
 * 아홉 컬럼은 {@code 21_users_drop_consent_columns.sql} 이 값을 여기로 옮긴 뒤 지웠다
 * (ADR-0020 이 사람의 판단으로 남긴 것을 2026-09-05 에 정했다).
 *
 * <p>{@code user} 를 허용하는 이유는 컨트롤러가 {@code @CurrentUser User} 로 주체를 받기
 * 때문이다({@code moderationweb} 과 같다). 그 밖으로 나가는 참조는 없다.
 */
@org.springframework.modulith.ApplicationModule(
        displayName = "Consent",
        allowedDependencies = { "user", "user :: entity" })
package com.heattrip.heat_trip_backend.consent;

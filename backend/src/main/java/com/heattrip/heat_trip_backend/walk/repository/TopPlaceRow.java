package com.heattrip.heat_trip_backend.walk.repository;

/**
 * "자주 가는 곳" 한 줄 — 이슈 #338.
 *
 * <p>{@link WalkTotals} 와 같은 이유로 {@code Object[]} 가 아니라 record 다 — 다중 컬럼
 * 집계를 그 타입으로 받으면 {@link ClassCastException} 이 난다(#145 에서 실측).
 *
 * <p>이름({@code title})은 묶음 안에서 {@code max()} 다. 같은 장소를 앱이 다른 이름으로 보낸
 * 적이 있으면(카탈로그가 갱신되면서 "서울숲" 이 "서울숲공원" 이 되는 식) 사전순 마지막이
 * 나온다. 묶는 기준은 이름이 아니라 {@code (source, contentId)} 이므로 <b>세는 값은 흔들리지
 * 않는다</b> — 이름 하나가 달라도 두 줄이 되지 않는다.
 *
 * @param source    카탈로그 출처 — {@code kto}·{@code vet}·{@code shop}·{@code trail}
 * @param contentId 카탈로그 식별자
 * @param title     화면에 쓸 이름
 * @param count     그 장소에서 걸은 횟수
 */
public record TopPlaceRow(String source, String contentId, String title, long count) {
}

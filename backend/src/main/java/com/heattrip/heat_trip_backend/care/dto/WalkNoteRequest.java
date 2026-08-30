package com.heattrip.heat_trip_backend.care.dto;

/**
 * 산책 주의사항 교체 요청 — 계약({@code openapi.yaml})의 {@code WalkNoteInput} 이다. 이슈 #76.
 *
 * <p><b>{@code {"notes": ["...", "..."]}} 가 아니다.</b> 계약이 예전에 그렇게 적었지만
 * 이슈 #76 이 정한 표는 <b>그룹당 한 장</b>({@code body} 하나)이다 — 이유는 {@code WalkNote}
 * 엔티티의 javadoc 에 있다. 앱이 줄 단위 목록으로 그리는 것은 화면의 표현이고, 보낼 때는
 * 편집된 <b>전체 본문</b>을 보낸다.
 *
 * @param body 500자까지. 넘으면 400 이다. 빈 문자열은 "다 지웠다" 는 정상 요청이다
 */
public record WalkNoteRequest(String body) {
}

package com.heattrip.heat_trip_backend.place.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonUnwrapped;

/**
 * 계약의 {@code PlaceDetail} 모양 — 이슈 #40.
 *
 * <p>계약이 {@code allOf: [Place, {overview, petInfo}]} 라 <b>평평한 객체</b>다.
 * {@code @JsonUnwrapped} 가 {@link #place} 의 필드를 한 단계 끌어올린다 — 중첩시키면
 * 계약과 다른 모양이 나간다.
 *
 * <p>{@code distM} 은 여기서 항상 {@code null} 이다. 상세 경로에는 <b>기준점이 없다</b> —
 * 사용자가 어디서 이 장소를 눌렀는지 서버가 모른다.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PlaceDetailDto(
        @JsonUnwrapped PlaceDto place,
        String overview,
        PetInfoDto petInfo) {
}

package com.heattrip.heat_trip_backend.consent.dto;

import java.util.List;

/**
 * {@code GET/PUT /api/consents} 응답 — 계약의 {@code Consents}.
 *
 * <p>벌거벗은 배열이 아니라 봉투인 이유: 나중에 "서버가 아는 최신 버전" 같은 것을 실어야
 * 할 때 배열은 자리가 없다. 지도 목록({@code /api/places/nearby})이 그 자리가 없어 잘림
 * 신호를 못 싣는 것을 봤다.
 */
public record ConsentsResponse(List<ConsentResponse> consents) {
}

package com.heattrip.heat_trip_backend.consent.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;

/** {@code PUT /api/consents} 본문 — 계약의 {@code ConsentsInput}. 문서가 넷이라 상한도 넷이다. */
public record ConsentsRequest(
        @NotEmpty @Size(max = 4) List<@Valid ConsentEntryRequest> consents) {
}

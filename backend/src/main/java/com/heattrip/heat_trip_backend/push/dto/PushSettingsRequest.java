package com.heattrip.heat_trip_backend.push.dto;

import jakarta.validation.constraints.NotNull;

/** 계약의 {@code PushSettingsInput}. {@code enabled} 가 없으면 400 — 빠진 필드를 false 로 읽으면 "{}" 가 끄기가 된다. */
public record PushSettingsRequest(@NotNull Boolean enabled) {
}

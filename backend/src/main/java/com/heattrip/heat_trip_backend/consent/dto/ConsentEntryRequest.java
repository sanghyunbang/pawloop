package com.heattrip.heat_trip_backend.consent.dto;

import com.heattrip.heat_trip_backend.consent.ConsentKind;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * 동의 한 항목 — 계약의 {@code ConsentInput}. 이슈 #190.
 *
 * <p>{@code version} 은 {@code v1.2} 모양이어야 한다. 자유 문자열로 두면 앱이 실수로
 * {@code 1.2} 나 {@code v1.2 } 를 보냈을 때 같은 문서가 다른 버전으로 쌓인다. 패턴은
 * 계약({@code ConsentInput.version.pattern})과 같아야 한다 — 계약 스펙 테스트가 견준다.
 *
 * <p>{@code agreed} 가 {@code Boolean} 인 이유: 빠지면 {@code false} 로 눕히는 대신 400 을
 * 내야 한다 — 빠진 것과 철회한 것은 다르다.
 */
public record ConsentEntryRequest(
        @NotNull ConsentKind kind,
        @NotNull @Pattern(regexp = VERSION_PATTERN) String version,
        @NotNull Boolean agreed) {

    /** 계약의 {@code ConsentInput.version.pattern} 과 같은 문자열이어야 한다. */
    public static final String VERSION_PATTERN = "^v[0-9]+\\.[0-9]+$";
}

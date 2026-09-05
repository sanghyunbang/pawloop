package com.heattrip.heat_trip_backend.consent.dto;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.ConsentTime;
import com.heattrip.heat_trip_backend.consent.entity.UserConsent;

import java.time.Instant;

/**
 * 문서 하나의 지금 상태 — 계약의 {@code Consent}. 이슈 #190.
 *
 * <p>{@code at} 은 {@link Instant} 다. 저장은 UTC {@code LocalDateTime} 이고 계약은
 * {@code date-time} 이라 오프셋이 붙어 나가야 한다({@code DateTimeFieldsAreInstantTest}).
 */
public record ConsentResponse(ConsentKind kind, String version, boolean agreed, Instant at) {

    public static ConsentResponse of(UserConsent row) {
        return new ConsentResponse(row.kind(), row.getVersion(), row.isAgreed(),
                ConsentTime.toInstant(row.getCreatedAt()));
    }
}

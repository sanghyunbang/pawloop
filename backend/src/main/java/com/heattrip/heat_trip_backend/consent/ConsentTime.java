package com.heattrip.heat_trip_backend.consent;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * {@code user_consent.created_at} 의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b>
 *
 * <p>{@code ChatTime}·{@code UserTime}·{@code ModerationTime} 과 같은 모양이다(#248). 모듈마다
 * 하나씩인 이유는 {@code allowedDependencies} 가 모듈 사이의 참조를 막기 때문이다.
 *
 * <p>이 값은 <b>서버가 찍는 순간</b>이다 — "언제 동의했는가" 를 다툴 때 근거가 되는 시각이라
 * 존이 섞이면 안 된다. {@code Clock} 만 받고 {@code clock.instant()} 만 읽는다 —
 * {@code ClockConfig} 의 존({@code Asia/Seoul})은 여기 관여하지 않는다.
 */
public final class ConsentTime {

    private ConsentTime() {
    }

    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    }

    public static Instant toInstant(LocalDateTime storedUtc) {
        return storedUtc.toInstant(ZoneOffset.UTC);
    }
}

package com.heattrip.heat_trip_backend.crew;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

/**
 * {@code crew} 의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #417.
 *
 * <p>여기 있는 시각은 전부 <b>서버가 찍는 순간</b>이다({@code created_at}·{@code updated_at}).
 * 사람이 고른 벽시계가 아니므로 UTC 로 눕히고, 응답은 {@link #toInstant} 로 오프셋을 붙인다 —
 * 계약({@code openapi.yaml} 의 {@code info.description})이 정한 규약이다.
 *
 * <h2>왜 클래스가 또 하나인가</h2>
 * <p>{@code ChatTime}·{@code ScheduleTime} 을 여기서 부르면 {@code crew} 가 그 모듈에 기대게
 * 된다. 두 줄을 옮겨 적는 쪽이 경계를 여는 것보다 싸다({@code DogTime} 과 같은 판단).
 */
public final class CrewTime {

    private CrewTime() {
    }

    /** 주입된 시계의 지금을 UTC 로. <b>시계의 존은 안 읽는다</b> — 빈은 {@code Asia/Seoul} 이다. */
    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 시계를 못 받는 자리 — 엔티티의 {@code @PrePersist}·{@code @PreUpdate} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}

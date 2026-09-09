package com.heattrip.heat_trip_backend.schedule;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

/**
 * {@code schedule} 의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #418.
 *
 * <h2>어느 값이 UTC 인가</h2>
 * <p>이 표에는 성격이 <b>다른 두 종류</b>의 시각이 있다.
 *
 * <ul>
 *   <li>{@code created_at}·{@code updated_at}·{@code done_at} — <b>서버가 찍는 순간</b>이다.
 *       계약({@code openapi.yaml} 의 {@code info.description})이 정한 대로 UTC 로 눕히고,
 *       응답은 {@link #toInstant} 로 오프셋을 붙여 내보낸다.</li>
 *   <li>{@code on_date}·{@code at_time} — <b>사람이 고른 벽시계</b>다. "10월 3일 10시 30분
 *       병원" 은 어느 시간대에서 보든 그 날 그 시각이라, <b>여기를 지나가지 않는다.</b>
 *       UTC 로 눕히면 밤 일정이 하루 넘어가고 달력이 다른 칸에 그린다.</li>
 * </ul>
 *
 * <p>이 구분이 {@code care} 가 {@code occurred_at} 에서 겪은 것과 같은 자리다(#247) — 하루
 * 경계를 갖는 값은 서비스 존이고, 서버가 찍는 순간은 UTC 다.
 *
 * <h2>왜 클래스가 또 하나인가</h2>
 * <p>{@code DogTime}·{@code CareTime} 을 여기서 부르면 {@code schedule} 이 그 모듈에 기대게
 * 된다. 두 줄을 옮겨 적는 쪽이 경계를 여는 것보다 싸다({@code DogTime} 과 같은 판단).
 * 마이크로초로 자르는 이유는 {@code datetime(6)} 컬럼에 저장한 값과 응답이 어긋나지 않게
 * 하려는 것이다.
 */
public final class ScheduleTime {

    private ScheduleTime() {
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

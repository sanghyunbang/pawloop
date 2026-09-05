package com.heattrip.heat_trip_backend.dog;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

/**
 * {@code dog} 의 시각 규약 — <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #306.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@code Dog} 의 {@code @PrePersist} 가 {@code LocalDateTime.now()} 를 썼다 — <b>JVM 기본
 * 존</b>이다. 개발 기계는 KST 고 배포 컨테이너는 UTC 라, 같은 코드가 환경마다 다른 값을 넣는다.
 * 계약({@code openapi.yaml} 의 {@code info.description})은 "표에 담기는 값은 UTC" 라고 정했고
 * {@code chat}·{@code user}·{@code community}·{@code moderation} 이 그렇게 눕힌다. {@code deleted_at}
 * 은 #156 에서 서비스 {@code Clock} 으로 UTC 를 찍었는데 {@code created_at} 만 JVM 존이었다.
 *
 * <p>{@code StoredTimestampsAreUtcTest} 가 잡지 못한 이유는 그 검사가 {@code chat}·{@code group}·
 * {@code user} 의 엔티티만 훑었기 때문이다 — #306 이 훑는 범위를 전체로 넓혔다.
 *
 * <h2>왜 클래스가 또 하나인가</h2>
 * <p>{@code UserTime}·{@code ChatTime} 을 여기서 부르면 {@code dog} 이 그 모듈에 기대게 된다.
 * 두 줄을 옮겨 적는 쪽이 경계를 여는 것보다 싸다({@code UserTime} 과 같은 판단). 마이크로초로
 * 자르는 이유는 {@code datetime(6)} 컬럼에 저장한 값과 응답이 어긋나지 않게 하려는 것이다
 * ({@code ModerationTime} 과 같다).
 */
public final class DogTime {

    private DogTime() {
    }

    /** 주입된 시계의 지금을 UTC 로. <b>시계의 존은 안 읽는다</b> — 빈은 {@code Asia/Seoul} 이다. */
    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 시계를 못 받는 자리 — 엔티티의 {@code @PrePersist} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 저장된 값을 다시 시각으로 세운다. 응답이 오프셋을 갖게 하는 자리다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}

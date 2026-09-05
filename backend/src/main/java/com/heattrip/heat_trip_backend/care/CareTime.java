package com.heattrip.heat_trip_backend.care;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

/**
 * {@code care} 의 <b>행 생성 시각</b> 규약 — {@code LocalDateTime} 인데 담긴 값이 UTC 다. 이슈 #306.
 *
 * <p>{@code CareLog.created_at} 만 다룬다. <b>{@code occurred_at} 은 여기 것이 아니다</b> — 그 값은
 * "오늘 누가 무엇을 했는가" 의 하루 경계를 갖는 값이라 서비스 존({@code ClockConfig.SERVICE_ZONE},
 * Asia/Seoul)의 벽시계이고, {@code CareService} 가 시계를 받아 직접 찍는다(#247). 두 컬럼의 존이
 * 다른 것은 의도다: 하나는 사람의 하루, 하나는 서버가 찍는 순간.
 *
 * <p>{@code CareLog} 의 {@code @PrePersist} 가 {@code LocalDateTime.now()}(JVM 존)를 쓰고 있었다 —
 * 응답에 안 나가는 값이라 화면이 틀린 적은 없지만, 개발 기계(KST)와 배포 컨테이너(UTC)가 같은
 * 표에 두 존을 섞어 넣는 것은 같다. {@code StoredTimestampsAreUtcTest} 가 전체 엔티티를 훑게 되면서
 * (#306) 여기도 규약대로 맞췄다. 다른 모듈의 {@code *Time} 을 부르지 않고 두 줄을 옮겨 적는 이유는
 * {@code UserTime} 과 같다 — 경계를 여는 것보다 싸다.
 */
public final class CareTime {

    private CareTime() {
    }

    /** 시계를 못 받는 자리 — 엔티티의 {@code @PrePersist} 가 부른다. */
    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
    }

    /** 저장된 값을 다시 시각으로 세운다. */
    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}

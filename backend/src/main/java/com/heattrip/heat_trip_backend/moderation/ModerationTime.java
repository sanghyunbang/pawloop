package com.heattrip.heat_trip_backend.moderation;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

/**
 * {@code report}·{@code report_snapshot}·{@code user_block} 의 시각 규약 —
 * <b>{@code LocalDateTime} 인데 담긴 값이 UTC 다.</b> 이슈 #248.
 *
 * <h2>왜 클래스로 뽑았나</h2>
 * <p>이 모듈 안에서 규약이 <b>이미 갈려 있었다.</b> {@code Reports} 는 자기 안에 private
 * {@code nowUtc()} 를 두고 UTC 로 넣는데, {@code Blocks} 는 {@code LocalDateTime.now(clock)}
 * 을 써서 <b>{@code Asia/Seoul}</b> 을 넣었고({@code ClockConfig} 가 박은 존),
 * {@code Block} 엔티티의 {@code @PrePersist} 는 <b>JVM 기본 존</b>을 썼다. 한 모듈, 세 존이다.
 *
 * <p>지금은 {@code Block.createdAt} 이 응답에 안 실려서 아무도 안 아팠다. 실리는 날 —
 * "언제부터 가렸나" 를 화면에 보여 주는 순간 — 조용히 9시간 어긋난다.
 *
 * <h2>왜 마이크로초까지 자르나</h2>
 * <p>컬럼이 {@code DATETIME(6)} 이라 나노초는 DB 에서 잘린다. 안 자르고 넣으면 응답으로
 * 돌려준 시각과 저장된 시각이 달라지고, 그 차이가 테스트에서만 보인다.
 *
 * <h2>왜 {@code ChatTime} 을 안 쓰나</h2>
 * <p>{@code moderation} 은 {@code allowedDependencies = &#123;&#125;} 다 — 나가는 참조가 0인
 * 것이 이 모듈의 요점이다({@code package-info}). 두 줄 때문에 그것을 열지 않는다.
 */
public final class ModerationTime {

    private ModerationTime() {
    }

    /** 주입된 시계의 지금을 UTC 로. <b>시계의 존은 안 읽는다.</b> */
    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)
                .truncatedTo(ChronoUnit.MICROS);
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

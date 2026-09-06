package com.heattrip.heat_trip_backend.push;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;

/**
 * 이 모듈의 표({@code device_token} · {@code push_preference})에 넣는 시각은 <b>UTC</b> 다 —
 * {@code ChatTime} 과 같은 규약이고, {@code StoredTimestampsAreUtcTest} 가 JVM 존을
 * {@code Asia/Seoul} 로 강제한 채 잰다.
 *
 * <p>{@code LocalDateTime.now()} 를 직접 부르지 않는다 — {@code TimeWritersAreUtcTest} 가
 * 이 모듈의 소스에서 그 호출을 찾으면 빨간불이다.
 */
public final class PushTime {

    private PushTime() {
    }

    public static LocalDateTime nowUtc() {
        return LocalDateTime.ofInstant(Instant.now(), ZoneOffset.UTC);
    }

    public static LocalDateTime nowUtc(Clock clock) {
        return LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    }

    public static Instant toInstant(LocalDateTime storedAsUtc) {
        return storedAsUtc == null ? null : storedAsUtc.toInstant(ZoneOffset.UTC);
    }
}

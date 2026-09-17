package com.heattrip.heat_trip_backend.walksafety;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

/**
 * 손으로 미는 시계. 캐시 수명을 재는 테스트가 함께 쓴다 — 시간을 흉내내지 않고 실제로 앞으로 민다.
 *
 * <p>{@code WalkSafetyStationCacheTest} 안에 있던 것을 {@code WalkSafetyDustCacheTest}(#668)가
 * 같이 쓰게 되면서 밖으로 꺼냈다. 두 테스트가 재는 것은 다르지만 재는 방법은 같다.
 */
final class MovableClock extends Clock {
    private Instant now;

    MovableClock(Instant start) {
        this.now = start;
    }

    void advance(Duration by) {
        now = now.plus(by);
    }

    @Override
    public ZoneOffset getZone() {
        return ZoneOffset.UTC;
    }

    @Override
    public Clock withZone(ZoneId zone) {
        return this;
    }

    @Override
    public Instant instant() {
        return now;
    }
}

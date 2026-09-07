package com.heattrip.heat_trip_backend.walksafety;

import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

/** 기준 시각 — 매시 40분에 그 시각(HH00) 실황이 나온다. 40분 전을 시 단위로 내린다(KST). */
class WalkSafetyServiceTest {
    @Test
    @DisplayName("14:10 KST → 13:00 실황 (14:00 실황은 14:40 에 나온다)")
    void beforeForty() {
        String[] base = WalkSafetyServiceTestAccess.base(Instant.parse("2026-09-07T05:10:00Z"));
        assertThat(base).containsExactly("20260907", "1300");
    }

    @Test
    @DisplayName("14:45 KST → 14:00 실황")
    void afterForty() {
        String[] base = WalkSafetyServiceTestAccess.base(Instant.parse("2026-09-07T05:45:00Z"));
        assertThat(base).containsExactly("20260907", "1400");
    }

    @Test
    @DisplayName("00:20 KST 는 전날 23:00 실황 — 날짜가 함께 넘어간다")
    void midnightBoundary() {
        String[] base = WalkSafetyServiceTestAccess.base(Instant.parse("2026-09-06T15:20:00Z"));
        assertThat(base).containsExactly("20260906", "2300");
    }

    /** {@link WalkSafetyService#kmaBase} 는 패키지 안이라 여기서 문을 하나 연다. */
    static final class WalkSafetyServiceTestAccess {
        static String[] base(Instant now) {
            return com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyServiceBaseAccess.kmaBase(now);
        }
    }
}

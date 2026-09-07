package com.heattrip.heat_trip_backend.walksafety.service;

import java.time.Instant;

/** 테스트가 {@link WalkSafetyService#kmaBase} 를 부르기 위한 문. 운영 코드는 부르지 않는다. */
public final class WalkSafetyServiceBaseAccess {
    private WalkSafetyServiceBaseAccess() {
    }

    public static String[] kmaBase(Instant now) {
        return WalkSafetyService.kmaBase(now);
    }
}

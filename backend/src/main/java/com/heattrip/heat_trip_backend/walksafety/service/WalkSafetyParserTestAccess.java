package com.heattrip.heat_trip_backend.walksafety.service;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.List;
import java.util.Optional;

/**
 * 테스트가 패키지 밖에서 {@link PublicDataJson} 을 부르기 위한 얇은 문. 운영 코드는 부르지 않는다.
 *
 * <p>파서를 public 으로 열면 모듈 공개 표면이 넓어지고, 테스트를 이 패키지 안에 두면 다른 모듈의
 * 테스트 배치 규약과 어긋난다(테스트는 모듈 루트 패키지에 둔다). 그래서 문 하나만 연다.
 */
public final class WalkSafetyParserTestAccess {
    private WalkSafetyParserTestAccess() {
    }

    public static Optional<PublicDataJson.Nowcast> nowcast(ObjectMapper mapper, String raw) {
        return PublicDataJson.parseNowcast(mapper, raw);
    }

    public static List<PublicDataJson.Station> stations(ObjectMapper mapper, String raw) {
        return PublicDataJson.parseStations(mapper, raw);
    }

    public static Optional<PublicDataJson.AirQuality> airQuality(ObjectMapper mapper, String raw) {
        return PublicDataJson.parseAirQuality(mapper, raw);
    }
}

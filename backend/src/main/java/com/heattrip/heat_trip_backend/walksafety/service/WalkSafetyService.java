package com.heattrip.heat_trip_backend.walksafety.service;

import com.heattrip.heat_trip_backend.walksafety.dto.WalkSafetyNowResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 격자 하나의 지금 관측값 — 기상청 실황 + (있으면) 가장 가까운 측정소의 미세먼지.
 *
 * <p><b>저장하지 않는다.</b> 격자별 응답을 10분 메모리 캐시할 뿐이고, 어느 사용자가 어느 격자를
 * 물었는지는 어디에도 남지 않는다(요청에 인증이 없다). 측정소 목록은 24시간 캐시 — 하루에
 * 한 번 받는 600행이다.
 */
@Service
public class WalkSafetyService {
    static final Duration NOW_TTL = Duration.ofMinutes(10);
    static final Duration STATIONS_TTL = Duration.ofHours(24);
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("yyyyMMdd");
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH00");

    private record Cached(WalkSafetyNowResponse value, Instant expiresAt) {
    }

    private record CachedStations(List<PublicDataJson.Station> value, Instant expiresAt) {
    }

    private final KmaNowcastClient kma;
    private final AirKoreaClient air;
    private final Clock clock;
    private final Map<Integer, Cached> nowCache = new ConcurrentHashMap<>();
    private volatile CachedStations stations;

    public WalkSafetyService(KmaNowcastClient kma, AirKoreaClient air, Clock clock) {
        this.kma = kma;
        this.air = air;
        this.clock = clock;
    }

    /**
     * @throws ResponseStatusException 400 격자 범위 밖 · 503 기상청 실황을 못 받음(키 없음 포함)
     */
    public WalkSafetyNowResponse now(int nx, int ny) {
        if (!KmaGrid.isValid(nx, ny)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "격자 번호가 범위 밖입니다.");
        }
        Instant at = clock.instant();
        int key = nx * 1000 + ny;
        Cached hit = nowCache.get(key);
        if (hit != null && hit.expiresAt().isAfter(at)) {
            return hit.value();
        }
        String[] base = kmaBase(at);
        PublicDataJson.Nowcast weather = kma.fetch(nx, ny, base[0], base[1])
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "지금 기상 정보를 받지 못했습니다."));
        Optional<PublicDataJson.AirQuality> dust = Optional.empty();
        String stationName = null;
        PublicDataJson.Station station = nearest(nx, ny, at);
        if (station != null) {
            dust = air.realtime(station.name());
            if (dust.isPresent()) {
                stationName = station.name();
            }
        }
        WalkSafetyNowResponse response = new WalkSafetyNowResponse(
                weather.tempC(), weather.humidity(), weather.rain1hMm(), weather.precipType(),
                dust.map(PublicDataJson.AirQuality::pm10).orElse(null),
                dust.map(PublicDataJson.AirQuality::pm25).orElse(null),
                stationName, at);
        nowCache.put(key, new Cached(response, at.plus(NOW_TTL)));
        return response;
    }

    /** 초단기실황의 기준 시각 — 매시 40분에 그 시각(HH00) 실황이 나온다. 40분 전을 시 단위로 내린다. */
    static String[] kmaBase(Instant now) {
        ZonedDateTime kst = now.atZone(KST).minusMinutes(40);
        return new String[] {kst.format(DATE), kst.format(TIME)};
    }

    private PublicDataJson.Station nearest(int nx, int ny, Instant at) {
        List<PublicDataJson.Station> list = stationList(at);
        if (list.isEmpty()) {
            return null;
        }
        double[] center = KmaGrid.toLatLng(nx, ny);
        PublicDataJson.Station best = null;
        double bestKm = Double.MAX_VALUE;
        for (PublicDataJson.Station s : list) {
            double d = KmaGrid.haversineKm(center[0], center[1], s.lat(), s.lng());
            if (d < bestKm) {
                bestKm = d;
                best = s;
            }
        }
        return best;
    }

    private List<PublicDataJson.Station> stationList(Instant at) {
        CachedStations cached = stations;
        if (cached != null && cached.expiresAt().isAfter(at)) {
            return cached.value();
        }
        List<PublicDataJson.Station> fresh = air.stations();
        // 승인 전(빈 목록)은 짧게만 기억한다 — 승인되면 한 시간 안에 붙는다.
        Duration ttl = fresh.isEmpty() ? Duration.ofHours(1) : STATIONS_TTL;
        stations = new CachedStations(fresh, at.plus(ttl));
        return fresh;
    }

    /** 테스트용 — 캐시를 비운다. */
    public void clearCaches() {
        nowCache.clear();
        stations = null;
    }
}

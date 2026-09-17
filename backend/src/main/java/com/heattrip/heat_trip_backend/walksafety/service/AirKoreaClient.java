package com.heattrip.heat_trip_backend.walksafety.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientRequestException;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Optional;

/**
 * 한국환경공단 에어코리아 — 측정소 목록({@code MsrstnInfoInqireSvc/getMsrstnList})과 측정소별
 * 실시간 측정({@code ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty}).
 *
 * <p>두 API 는 공공데이터포털에서 <b>따로 활용신청</b>해야 한다. 승인 전에는
 * {@code SERVICE_KEY_IS_NOT_REGISTERED_ERROR} 가 오고 여기서는 빈 목록/빈 값이 된다 —
 * 서비스는 그때 미세먼지 없이 기온만 준다.
 */
@Component
public class AirKoreaClient {
    private static final Logger log = LoggerFactory.getLogger(AirKoreaClient.class);
    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(6);

    /**
     * 재시도가 붙는 호출 하나의 상한. 둘을 더해도 {@link #CALL_TIMEOUT} 과 같다 —
     * 다시 걸어 보는 대가로 사람이 기다리는 시간이 늘면 안 된다(#668).
     */
    private static final Duration RETRIED_CALL_TIMEOUT = Duration.ofSeconds(3);

    private final WebClient client;
    private final ObjectMapper objectMapper;
    private final String serviceKey;

    public AirKoreaClient(@Qualifier("airKoreaWebClient") WebClient client,
                          ObjectMapper objectMapper,
                          @Value("${app.public-data.service-key:}") String serviceKey) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey == null ? "" : serviceKey.strip();
    }

    /** 전국 측정소 목록(600곳 남짓). 승인 전이거나 실패하면 빈 목록. */
    public List<PublicDataJson.Station> stations() {
        if (serviceKey.isEmpty()) {
            return List.of();
        }
        String raw = get("/MsrstnInfoInqireSvc/getMsrstnList?serviceKey=" + serviceKey
                + "&returnType=json&numOfRows=1000&pageNo=1", "측정소 목록");
        return raw == null ? List.of() : PublicDataJson.parseStations(objectMapper, raw);
    }

    /**
     * 측정소 하나의 지금 값. 승인 전이거나 두 번 다 실패하면 없음.
     *
     * <p><b>연결이 안 되면 한 번 더 건다.</b> 2026-09-17 00:01 KST 에 이 호출이 딱 한 번
     * {@link WebClientRequestException} 으로 실패했고, 그 값 없는 응답이 서버 캐시와 앱 캐시를
     * 타고 최대 40분을 갔다(#668). 연결 자체가 안 선 것은 응답을 받아 놓고 내용이 틀린 것과
     * 다르다 — 게이트웨이에 부담을 주지 않고, 다음 번에 대개 붙는다. 그래서 여기만 다시 건다.
     * 측정소 목록은 안 그런다 — 그쪽은 이미 빈 목록을 5분만 기억한다(EMPTY_STATIONS_TTL).
     */
    public Optional<PublicDataJson.AirQuality> realtime(String stationName) {
        if (serviceKey.isEmpty() || stationName == null || stationName.isBlank()) {
            return Optional.empty();
        }
        String raw = getRetryingOnceWhenUnreachable(
                "/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty?serviceKey=" + serviceKey
                        + "&returnType=json&numOfRows=1&pageNo=1&dataTerm=DAILY&ver=1.3"
                        + "&stationName=" + URLEncoder.encode(stationName, StandardCharsets.UTF_8),
                "실시간 측정");
        return raw == null ? Optional.empty() : PublicDataJson.parseAirQuality(objectMapper, raw);
    }

    private String get(String uri, String what) {
        try {
            return call(uri, CALL_TIMEOUT);
        } catch (RuntimeException e) {
            log.warn("에어코리아 {} 호출 실패 — cause={}", what, e.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * {@link WebClientRequestException}(연결 자체가 안 섰다) 일 때만 한 번 더 건다.
     * 그 외의 실패는 다시 걸어도 같은 답이 오므로 바로 포기한다.
     */
    private String getRetryingOnceWhenUnreachable(String uri, String what) {
        try {
            return call(uri, RETRIED_CALL_TIMEOUT);
        } catch (WebClientRequestException unreachable) {
            log.warn("에어코리아 {} 연결 실패 — 한 번 더 건다. cause={}",
                    what, unreachable.getClass().getSimpleName());
        } catch (RuntimeException e) {
            log.warn("에어코리아 {} 호출 실패 — cause={}", what, e.getClass().getSimpleName());
            return null;
        }
        try {
            return call(uri, RETRIED_CALL_TIMEOUT);
        } catch (RuntimeException e) {
            log.warn("에어코리아 {} 호출 실패 — 다시 걸어도 안 됐다. cause={}",
                    what, e.getClass().getSimpleName());
            return null;
        }
    }

    private String call(String uri, Duration timeout) {
        return client.get()
                .uri(uri)
                .exchangeToMono(r -> r.bodyToMono(String.class).defaultIfEmpty(""))
                .timeout(timeout)
                .block();
    }
}

package com.heattrip.heat_trip_backend.walksafety.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

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

    /** 측정소 하나의 지금 값. 승인 전이거나 실패하면 없음. */
    public Optional<PublicDataJson.AirQuality> realtime(String stationName) {
        if (serviceKey.isEmpty() || stationName == null || stationName.isBlank()) {
            return Optional.empty();
        }
        String raw = get("/ArpltnInforInqireSvc/getMsrstnAcctoRltmMesureDnsty?serviceKey=" + serviceKey
                + "&returnType=json&numOfRows=1&pageNo=1&dataTerm=DAILY&ver=1.3"
                + "&stationName=" + URLEncoder.encode(stationName, StandardCharsets.UTF_8), "실시간 측정");
        return raw == null ? Optional.empty() : PublicDataJson.parseAirQuality(objectMapper, raw);
    }

    private String get(String uri, String what) {
        try {
            return client.get()
                    .uri(uri)
                    .exchangeToMono(r -> r.bodyToMono(String.class).defaultIfEmpty(""))
                    .timeout(CALL_TIMEOUT)
                    .block();
        } catch (RuntimeException e) {
            log.warn("에어코리아 {} 호출 실패 — cause={}", what, e.getClass().getSimpleName());
            return null;
        }
    }
}

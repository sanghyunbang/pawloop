package com.heattrip.heat_trip_backend.walksafety.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.Optional;

/**
 * 기상청 단기예보 조회서비스의 초단기실황({@code getUltraSrtNcst}) 한 번.
 *
 * <p>키는 URI 를 조립할 때만 붙이고 URL 은 로그에 찍지 않는다({@code KtoWebClientConfig} 의 규칙).
 * 실패는 전부 {@link Optional#empty()} — 호출부가 값을 지어내지 않는다.
 */
@Component
public class KmaNowcastClient {
    private static final Logger log = LoggerFactory.getLogger(KmaNowcastClient.class);
    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(6);

    private final WebClient client;
    private final ObjectMapper objectMapper;
    private final String serviceKey;

    public KmaNowcastClient(@Qualifier("kmaWebClient") WebClient client,
                            ObjectMapper objectMapper,
                            @Value("${app.public-data.service-key:}") String serviceKey) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey == null ? "" : serviceKey.strip();
    }

    /** 키가 없으면 아무것도 부르지 않는다 — 카드가 없는 것이 맞다. */
    public boolean enabled() {
        return !serviceKey.isEmpty();
    }

    /**
     * @param baseDate {@code yyyyMMdd}(KST)
     * @param baseTime {@code HH00}(KST) — 매시 40분에 그 시각 실황이 나온다
     */
    public Optional<PublicDataJson.Nowcast> fetch(int nx, int ny, String baseDate, String baseTime) {
        if (!enabled()) {
            return Optional.empty();
        }
        String query = "serviceKey=" + serviceKey
                + "&pageNo=1&numOfRows=10&dataType=JSON"
                + "&base_date=" + baseDate
                + "&base_time=" + baseTime
                + "&nx=" + nx + "&ny=" + ny;
        String raw;
        try {
            raw = client.get()
                    .uri("/getUltraSrtNcst?" + query)
                    .exchangeToMono(r -> r.bodyToMono(String.class).defaultIfEmpty(""))
                    .timeout(CALL_TIMEOUT)
                    .block();
        } catch (RuntimeException e) {
            // 예외 메시지에 URL(=키)이 섞일 수 있어 타입 이름만 남긴다.
            log.warn("기상청 초단기실황 호출 실패 — nx={} ny={} cause={}", nx, ny, e.getClass().getSimpleName());
            return Optional.empty();
        }
        Optional<PublicDataJson.Nowcast> parsed = PublicDataJson.parseNowcast(objectMapper, raw);
        if (parsed.isEmpty()) {
            log.warn("기상청 초단기실황 응답에 기온이 없다 — nx={} ny={} base={} {}", nx, ny, baseDate, baseTime);
        }
        return parsed;
    }
}

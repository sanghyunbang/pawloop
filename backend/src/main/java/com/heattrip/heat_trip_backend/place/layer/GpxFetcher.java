package com.heattrip.heat_trip_backend.place.layer;

import com.heattrip.heat_trip_backend.config.KtoWebClientConfig;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.net.URI;
import java.time.Duration;
import java.util.Optional;

/**
 * 두루누비 GPX 파일을 받아 온다 — 이슈 #291.
 *
 * <p>코스 목록이 주는 {@code gpxpath} 는 두루누비 웹서버의 파일 주소다. 게이트웨이가 아니라
 * 예산에 안 잡히고 서비스키도 안 붙는다. 다만 <b>남의 서버가 준 URL 을 그대로 여는 자리</b>라
 * {@code http(s)} 만 허용하고 크기·시간을 자른다.
 */
@Service
public class GpxFetcher {

    private static final Logger log = LoggerFactory.getLogger(GpxFetcher.class);

    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(20);

    private final WebClient client;

    public GpxFetcher(@Qualifier(KtoWebClientConfig.GPX) WebClient client) {
        this.client = client;
    }

    public Optional<String> fetch(String url) {
        URI uri;
        try {
            uri = URI.create(url.strip());
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
        String scheme = uri.getScheme();
        if (scheme == null || !(scheme.equalsIgnoreCase("http") || scheme.equalsIgnoreCase("https"))
                || uri.getHost() == null) {
            log.warn("GPX 주소가 http(s) 가 아니다 — 건너뛴다");
            return Optional.empty();
        }
        try {
            String body = client.get()
                    .uri(uri)
                    .exchangeToMono(response -> response.statusCode().is2xxSuccessful()
                            ? response.bodyToMono(String.class).defaultIfEmpty("")
                            : response.releaseBody().then(reactor.core.publisher.Mono.just("")))
                    .timeout(CALL_TIMEOUT)
                    .block();
            return (body == null || body.isBlank()) ? Optional.empty() : Optional.of(body);
        } catch (RuntimeException e) {
            log.warn("GPX 를 못 받았다 — host={} cause={}", uri.getHost(), e.getClass().getSimpleName());
            return Optional.empty();
        }
    }
}

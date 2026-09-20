package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.heattrip.heat_trip_backend.place.OrsProperties;
import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

/**
 * OpenRouteService 의 {@code POST /v2/directions/foot-walking/geojson} — 이슈 #725.
 *
 * <p>GeoJSON 끝점을 쓰는 이유: 기본 끝점은 선을 <b>인코딩된 폴리라인</b>으로 주어 풀어야 하는데,
 * GeoJSON 은 {@code [경도, 위도]} 를 그대로 준다(실측 2026-09-20, 71점 · 2,130m).
 *
 * <p><b>키는 헤더로만 나간다.</b> URL 에 싣지 않으므로 스프링의 URL 로그(#192)에 남지 않는다.
 * 여기서도 URL·본문을 찍지 않고 상태코드와 예외 타입 이름만 남긴다.
 *
 * <p>이 클래스는 통합 검사가 가짜로 갈아 끼우므로 {@code WebClientOrsRoutingClientTest} 가 JDK 의
 * {@code HttpServer} 로 가짜 ORS 를 띄워 <b>진짜 HTTP</b> 로 잰다 — 헤더 · 본문 · 406 규칙.
 */
@Component
public class WebClientOrsRoutingClient implements OrsRoutingClient {

    private static final Logger log = LoggerFactory.getLogger(WebClientOrsRoutingClient.class);

    private static final String DIRECTIONS = "/v2/directions/foot-walking/geojson";

    private final WebClient client;
    private final OrsProperties properties;
    private final ObjectMapper objectMapper;

    public WebClientOrsRoutingClient(WebClient.Builder builder,
                                    OrsProperties properties,
                                    ObjectMapper objectMapper) {
        this.properties = properties;
        this.objectMapper = objectMapper;
        HttpClient http = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, properties.getConnectTimeoutMs())
                .responseTimeout(Duration.ofMillis(properties.getReadTimeoutMs()))
                .doOnConnected(conn -> conn.addHandlerLast(
                        new ReadTimeoutHandler(properties.getReadTimeoutMs(), TimeUnit.MILLISECONDS)));
        this.client = builder
                .baseUrl(properties.getBaseUrl())
                .clientConnector(new ReactorClientHttpConnector(http))
                .build();
    }

    @Override
    public boolean isConfigured() {
        return properties.hasKey();
    }

    @Override
    public Optional<Loop> roundTrip(double lat, double lng, int lengthM, int points, int seed) {
        if (!isConfigured()) {
            return Optional.empty();
        }
        ObjectNode body = objectMapper.createObjectNode();
        body.putArray("coordinates").addArray().add(lng).add(lat);
        ObjectNode roundTrip = body.putObject("options").putObject("round_trip");
        roundTrip.put("length", lengthM);
        roundTrip.put("points", points);
        roundTrip.put("seed", seed);

        String raw;
        try {
            raw = client.post()
                    .uri(DIRECTIONS)
                    .header(HttpHeaders.AUTHORIZATION, properties.getApiKey())
                    .contentType(MediaType.APPLICATION_JSON)
                    // GeoJSON 끝점은 application/geo+json 을 준다 — application/json 만 받겠다고
                    // 하면 406 으로 전부 거절된다(dev 에서 처음 부르자 실측). 무엇이든 받는다.
                    .accept(MediaType.ALL)
                    .bodyValue(body.toString())
                    // 4xx/5xx 도 본문을 버리지 않고 상태만 남긴다 — retrieve() 는 예외를 던지며 본문을 버린다.
                    .exchangeToMono(response -> {
                        if (response.statusCode().is2xxSuccessful()) {
                            return response.bodyToMono(String.class).defaultIfEmpty("");
                        }
                        log.warn("ORS 가 거절했다 — status={} seed={} length={}",
                                response.statusCode().value(), seed, lengthM);
                        return response.releaseBody().then(Mono.just(""));
                    })
                    .timeout(Duration.ofMillis(properties.getReadTimeoutMs() + 1000L))
                    .block();
        } catch (RuntimeException e) {
            // 예외 메시지에 URL·본문이 섞일 수 있어 타입 이름만 남긴다.
            log.warn("ORS 호출 실패 — seed={} cause={}", seed, e.getClass().getSimpleName());
            return Optional.empty();
        }
        if (raw == null || raw.isBlank()) {
            return Optional.empty();
        }
        return parse(raw);
    }

    private Optional<Loop> parse(String raw) {
        try {
            JsonNode feature = objectMapper.readTree(raw).path("features").path(0);
            JsonNode coordinates = feature.path("geometry").path("coordinates");
            JsonNode summary = feature.path("properties").path("summary");
            if (!coordinates.isArray() || coordinates.size() < 2 || !summary.has("distance")) {
                log.warn("ORS 응답에 선이나 길이가 없다");
                return Optional.empty();
            }
            List<double[]> line = new ArrayList<>(coordinates.size());
            for (JsonNode point : coordinates) {
                if (point.size() >= 2) {
                    line.add(new double[] {point.get(0).asDouble(), point.get(1).asDouble()});
                }
            }
            return Optional.of(new Loop(summary.path("distance").asDouble(),
                    summary.path("duration").asDouble(), line));
        } catch (Exception e) {
            log.warn("ORS 응답을 읽지 못했다 — cause={}", e.getClass().getSimpleName());
            return Optional.empty();
        }
    }
}

package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.OrsProperties;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 진짜 HTTP 로 ORS 를 부르는 쪽 — 이슈 #725. 가짜 ORS 를 JDK 의 {@link HttpServer} 로 띄워 잰다.
 *
 * <p>왜 필요한가: 통합 검사는 {@code OrsRoutingClient} 를 가짜로 꽂으므로 <b>이 클래스는 아무 검사도
 * 안 지났다.</b> 실제로 dev 서버에서 처음 부르자 ORS 가 전부 거절했다 — {@code Accept: application/json}
 * 만 보냈는데 GeoJSON 끝점은 {@code application/geo+json} 을 주기 때문이다(2026-09-20 실측). 이 가짜
 * ORS 는 그 규칙을 그대로 흉내 낸다: 받을 수 있는 종류에 {@code geo+json} 이나 {@code *&#47;*} 가 없으면 406.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21) — {@code WebClient.builder()} 를 직접 만든다.
 */
class WebClientOrsRoutingClientTest {

    private static final String GEOJSON = """
            {"type":"FeatureCollection","features":[{"type":"Feature",
             "properties":{"summary":{"distance":2130.2,"duration":1533.8}},
             "geometry":{"type":"LineString","coordinates":[[127.037552,37.544284],[127.0405,37.5462],[127.037552,37.544284]]}}]}
            """;

    private HttpServer server;
    private final List<Map<String, String>> seenHeaders = new CopyOnWriteArrayList<>();
    private final List<String> seenBodies = new CopyOnWriteArrayList<>();
    private volatile int statusToReturn = 200;

    @BeforeEach
    void startFakeOrs() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v2/directions/foot-walking/geojson", exchange -> {
            String accept = exchange.getRequestHeaders().getFirst("Accept");
            seenHeaders.add(Map.of(
                    "Authorization", String.valueOf(exchange.getRequestHeaders().getFirst("Authorization")),
                    "Accept", String.valueOf(accept),
                    "Content-Type", String.valueOf(exchange.getRequestHeaders().getFirst("Content-Type"))));
            try (InputStream in = exchange.getRequestBody()) {
                seenBodies.add(new String(in.readAllBytes(), StandardCharsets.UTF_8));
            }
            // 진짜 ORS 의 규칙 — GeoJSON 끝점은 geo+json 을 준다. 그것을 못 받겠다는 요청은 406.
            boolean acceptable = accept == null || accept.contains("*/*") || accept.contains("geo+json");
            int status = !acceptable ? 406 : statusToReturn;
            byte[] body = (status == 200 ? GEOJSON : "{\"error\":{\"code\":" + status + "}}")
                    .getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type",
                    status == 200 ? "application/geo+json;charset=UTF-8" : "application/json");
            exchange.sendResponseHeaders(status, body.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        });
        server.start();
    }

    @AfterEach
    void stopFakeOrs() {
        server.stop(0);
    }

    private WebClientOrsRoutingClient client(String key) {
        OrsProperties properties = new OrsProperties();
        properties.setApiKey(key);
        properties.setBaseUrl("http://127.0.0.1:" + server.getAddress().getPort());
        properties.setReadTimeoutMs(3000);
        return new WebClientOrsRoutingClient(WebClient.builder(), properties, new ObjectMapper());
    }

    @Test
    @DisplayName("키는 Authorization 헤더로, 좌표는 [경도, 위도] 로, 왕복 옵션과 함께 — 그리고 GeoJSON 을 받을 수 있다고 말한다")
    void sendsWhatOrsExpectsAndParsesGeoJson() {
        Optional<OrsRoutingClient.Loop> loop = client("test-key-123").roundTrip(37.5443, 127.0376, 2000, 3, 7);

        assertThat(loop).isPresent();
        assertThat(loop.get().distanceM()).isEqualTo(2130.2);
        assertThat(loop.get().durationS()).isEqualTo(1533.8);
        assertThat(loop.get().lngLat()).hasSize(3);
        assertThat(loop.get().lngLat().get(0)).containsExactly(127.037552, 37.544284);

        Map<String, String> headers = seenHeaders.get(0);
        assertThat(headers.get("Authorization")).isEqualTo("test-key-123");
        assertThat(headers.get("Accept"))
                .as("GeoJSON 끝점은 geo+json 을 준다 — application/json 만 받겠다고 하면 406 이다(실측)")
                .satisfiesAnyOf(a -> assertThat(a).contains("*/*"), a -> assertThat(a).contains("geo+json"));
        assertThat(headers.get("Content-Type")).contains("application/json");
        assertThat(seenBodies.get(0))
                .contains("\"coordinates\":[[127.0376,37.5443]]")
                .contains("\"round_trip\":{\"length\":2000,\"points\":3,\"seed\":7}");
    }

    @Test
    @DisplayName("거절(403)이나 이상한 본문이면 빈 값 — 던지지 않는다")
    void rejectionIsEmptyNotAnException() {
        statusToReturn = 403;
        assertThat(client("test-key-123").roundTrip(37.5443, 127.0376, 2000, 3, 1)).isEmpty();
    }

    @Test
    @DisplayName("키가 없으면 부르지도 않는다")
    void noKeyMeansNoCall() {
        assertThat(client("").roundTrip(37.5443, 127.0376, 2000, 3, 1)).isEmpty();
        assertThat(seenBodies).isEmpty();
    }
}

package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.config.KtoWebClientConfig;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 관광공사 두루누비 걷기여행길 호출 — 이슈 #291.
 *
 * <p>{@code https://apis.data.go.kr/B551011/Durunubi/courseList} — KTO 반려동반 서비스와
 * 같은 기관, 같은 게이트웨이, 같은 서비스키다. 다만 공공데이터포털에서 이 API 에 따로
 * "활용신청" 을 해야 열린다(자동 승인). 안 열려 있으면 {@code returnReasonCode=30} 이다 —
 * 2026-09-06 실측이 그 응답이었다.
 *
 * <h2>한 코스가 주는 것</h2>
 * <p>코스 이름·거리(km)·소요시간(분)·난이도·시군·요약과 <b>GPX 파일의 URL</b>({@code gpxpath}).
 * 코스의 좌표는 목록에 없다. 선은 {@link GpxFetcher} 가 그 URL 을 받아 {@link GpxParser} 로
 * 읽는다. "중간에 변환한다" 는 것이 이것이다 — 선을 받아서, 시작점은 카탈로그의 점으로,
 * 선 자체는 {@code trail_route} 로 나눠 담는다.
 *
 * <p>{@code brdDiv=DNWW} 는 걷기길이다(명세: "걷기 길만 제공되고 있음").
 */
@Service
public class DurunubiApiClient {

    private static final Logger log = LoggerFactory.getLogger(DurunubiApiClient.class);

    /** KTO 가 "정상" 이라고 말하는 값 — {@code KtoApiClient.RESULT_OK} 와 같다. */
    private static final String RESULT_OK = "0000";

    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(12);

    /** 코스 목록 한 줄. 필드 이름은 명세의 것을 우리말로 옮긴 것이다. */
    public record Course(String courseId,
                         String name,
                         String routeIdx,
                         Double distanceKm,
                         Integer minutes,
                         Integer level,
                         String cycle,
                         String sigun,
                         String gpxUrl) {

        /** 카드 한 줄 — "12.3km · 약 4시간 · 보통". 모르는 값은 안 그린다. */
        public String summary() {
            List<String> parts = new ArrayList<>();
            if (distanceKm != null && distanceKm > 0) {
                parts.add(distanceKm % 1 == 0 ? "%.0fkm".formatted(distanceKm) : "%.1fkm".formatted(distanceKm));
            }
            if (minutes != null && minutes > 0) {
                int h = minutes / 60;
                int m = minutes % 60;
                parts.add("약 " + (h > 0 ? h + "시간" : "") + (m > 0 ? (h > 0 ? " " : "") + m + "분" : ""));
            }
            if (level != null) {
                parts.add(switch (level) {
                    case 1 -> "쉬움";
                    case 2 -> "보통";
                    case 3 -> "어려움";
                    default -> "난이도 " + level;
                });
            }
            if (cycle != null && !cycle.isBlank()) {
                parts.add(cycle);
            }
            return String.join(" · ", parts);
        }
    }

    private final WebClient client;
    private final ObjectMapper objectMapper;
    private final String serviceKey;
    private final LayerCatalogProperties properties;

    public DurunubiApiClient(@Qualifier(KtoWebClientConfig.DURUNUBI) WebClient client,
                             ObjectMapper objectMapper,
                             @Value("${TOUR.API.SECRET}") String serviceKey,
                             LayerCatalogProperties properties) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey;
        this.properties = properties;
    }

    public KtoApiClient.Result<List<Course>> fetchCoursePage(int pageNo) {
        String query = "serviceKey=" + serviceKey
                + "&MobileOS=ETC&MobileApp=heattrip&_type=json"
                + "&numOfRows=" + properties.getDurunubiPageSize() + "&pageNo=" + pageNo
                + "&brdDiv=DNWW";

        String raw;
        try {
            raw = client.get()
                    .uri("/courseList?" + query)
                    .exchangeToMono(response -> response.bodyToMono(String.class).defaultIfEmpty(""))
                    .timeout(CALL_TIMEOUT)
                    .block();
        } catch (RuntimeException e) {
            log.warn("두루누비 호출 실패 — page={} cause={}", pageNo, e.getClass().getSimpleName());
            return new KtoApiClient.Result.Failed<>(null, e.getClass().getSimpleName());
        }

        if (raw == null || raw.isBlank()) {
            return new KtoApiClient.Result.Failed<>(null, "empty-body");
        }

        DataGoKrEnvelope.Parsed parsed;
        try {
            parsed = DataGoKrEnvelope.parse(objectMapper, raw);
        } catch (Exception e) {
            log.warn("두루누비 응답을 읽지 못했다 — page={} ({})", pageNo, e.getClass().getSimpleName());
            return new KtoApiClient.Result.Failed<>(null, "unreadable-body");
        }

        if (parsed.gatewayRejected()) {
            log.warn("공공데이터포털 게이트웨이가 거절했다 — durunubi returnReasonCode={} msg={}",
                    parsed.gatewayError(), parsed.gatewayMessage());
            return new KtoApiClient.Result.Failed<>(parsed.gatewayError(), parsed.gatewayMessage());
        }
        if (parsed.resultCode() == null || !RESULT_OK.equals(parsed.resultCode())) {
            log.warn("두루누비가 거절했다 — resultCode={} resultMsg={}", parsed.resultCode(), parsed.resultMsg());
            return new KtoApiClient.Result.Failed<>(parsed.resultCode(), parsed.resultMsg());
        }

        List<Course> courses = new ArrayList<>();
        for (JsonNode item : parsed.items()) {
            toCourse(item).ifPresent(courses::add);
        }
        if (courses.isEmpty()) {
            return new KtoApiClient.Result.Empty<>();
        }
        return new KtoApiClient.Result.Ok<>(courses, parsed.totalCount());
    }

    /** 코스 하나. 이름·번호·GPX 주소 중 하나라도 없으면 지도에 올릴 수 없다. */
    static Optional<Course> toCourse(JsonNode item) {
        String id = text(item, "crsIdx");
        String name = text(item, "crsKorNm");
        String gpx = text(item, "gpxpath");
        if (id == null || name == null || gpx == null) {
            return Optional.empty();
        }
        return Optional.of(new Course(
                id,
                name,
                text(item, "routeIdx"),
                decimal(item, "crsDstnc"),
                integer(item, "crsTotlRqrmHour"),
                integer(item, "crsLevel"),
                text(item, "crsCycle"),
                text(item, "sigun"),
                gpx));
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String text = value.asText().strip();
        return text.isEmpty() ? null : text;
    }

    private static Double decimal(JsonNode node, String field) {
        String raw = text(node, field);
        if (raw == null) {
            return null;
        }
        try {
            return Double.parseDouble(raw.replace(",", ""));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static Integer integer(JsonNode node, String field) {
        Double value = decimal(node, field);
        return value == null ? null : (int) Math.round(value);
    }
}

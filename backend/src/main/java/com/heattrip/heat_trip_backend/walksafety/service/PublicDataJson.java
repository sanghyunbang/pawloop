package com.heattrip.heat_trip_backend.walksafety.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 공공데이터포털 응답 읽기 — 기상청 초단기실황 · 에어코리아 측정소/실시간. 전부 순수 함수.
 *
 * <p>게이트웨이 오류({@code OpenAPI_ServiceResponse.cmmMsgHeader}, 예: 등록되지 않은 서비스키)와
 * 서비스 오류({@code response.header.resultCode != 00})는 둘 다 "없음" 이다 — 호출부가 값을
 * 지어내지 않게 {@link Optional#empty()} 로 돌려준다. XML 로 오는 오류 본문("&lt;" 로 시작)도 없음이다.
 *
 * <p>{@code place.layer.DataGoKrEnvelope} 와 같은 봉투지만 그 클래스는 그 모듈 안의 것이라
 * 여기서 부르지 않는다(모듈 경계). 필요한 만큼만 다시 적었다.
 */
public final class PublicDataJson {
    /** 기상청 초단기실황 한 묶음. 기온이 없으면 묶음이 없다. */
    public record Nowcast(double tempC, Integer humidity, Double rain1hMm, Integer precipType) {
    }

    /** 에어코리아 측정소 한 곳. {@code dmX} 가 위도, {@code dmY} 가 경도(명세 표기 그대로). */
    public record Station(String name, double lat, double lng) {
    }

    /** 에어코리아 실시간 한 행. 값이 "-" 면 {@code null}. */
    public record AirQuality(Integer pm10, Integer pm25) {
    }

    private PublicDataJson() {
    }

    public static Optional<Nowcast> parseNowcast(ObjectMapper mapper, String raw) {
        List<JsonNode> items = okItems(mapper, raw);
        if (items == null) {
            return Optional.empty();
        }
        Double temp = null;
        Integer humidity = null;
        Double rain = null;
        Integer pty = null;
        for (JsonNode it : items) {
            String category = it.path("category").asText("");
            String value = it.path("obsrValue").asText("");
            switch (category) {
                case "T1H" -> temp = parseDouble(value);
                case "REH" -> humidity = parseInt(value);
                case "RN1" -> rain = parseDouble(value);
                case "PTY" -> pty = parseInt(value);
                default -> {
                }
            }
        }
        if (temp == null) {
            return Optional.empty();
        }
        return Optional.of(new Nowcast(temp, humidity, rain, pty));
    }

    public static List<Station> parseStations(ObjectMapper mapper, String raw) {
        List<JsonNode> items = okItems(mapper, raw);
        if (items == null) {
            return List.of();
        }
        List<Station> out = new ArrayList<>(items.size());
        for (JsonNode it : items) {
            Double lat = parseDouble(it.path("dmX").asText(""));
            Double lng = parseDouble(it.path("dmY").asText(""));
            String name = it.path("stationName").asText("");
            if (lat == null || lng == null || name.isBlank()) {
                continue;
            }
            out.add(new Station(name, lat, lng));
        }
        return out;
    }

    public static Optional<AirQuality> parseAirQuality(ObjectMapper mapper, String raw) {
        List<JsonNode> items = okItems(mapper, raw);
        if (items == null || items.isEmpty()) {
            return Optional.empty();
        }
        JsonNode row = items.get(0);
        return Optional.of(new AirQuality(parseInt(row.path("pm10Value").asText("")),
                parseInt(row.path("pm25Value").asText(""))));
    }

    /**
     * 봉투를 열어 {@code body.items(.item)} 를 배열로. 게이트웨이 오류·서비스 오류·XML·깨진 본문이면
     * {@code null} — 빈 목록과 구분한다(빈 목록은 "정상인데 0건").
     */
    private static List<JsonNode> okItems(ObjectMapper mapper, String raw) {
        if (raw == null || raw.isBlank() || raw.strip().startsWith("<")) {
            return null;
        }
        JsonNode root;
        try {
            root = mapper.readTree(raw);
        } catch (Exception e) {
            return null;
        }
        if (!root.path("OpenAPI_ServiceResponse").isMissingNode()) {
            return null;
        }
        JsonNode response = root.path("response");
        String code = response.path("header").path("resultCode").asText("");
        if (!code.isEmpty() && !"00".equals(code) && !"0".equals(code) && !"0000".equals(code)) {
            return null;
        }
        JsonNode items = response.path("body").path("items");
        JsonNode item = items.isObject() ? items.path("item") : items;
        if (item.isArray()) {
            List<JsonNode> out = new ArrayList<>(item.size());
            item.forEach(out::add);
            return out;
        }
        if (item.isObject()) {
            return List.of(item);
        }
        return response.path("body").isMissingNode() ? null : List.of();
    }

    private static Double parseDouble(String v) {
        try {
            return v == null || v.isBlank() ? null : Double.valueOf(v.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static Integer parseInt(String v) {
        Double d = parseDouble(v);
        return d == null ? null : (int) Math.round(d);
    }
}

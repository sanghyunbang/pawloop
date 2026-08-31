package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.config.KtoWebClientConfig;
import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * 관광공사(KTO) 호출 — 이슈 #40. <b>서비스키가 사는 유일한 자리다.</b>
 *
 * <h2>KTO 는 실패를 HTTP 200 으로 준다</h2>
 * <p>상태 코드가 아니라 본문의 {@code response.header.resultCode} 가 진짜 결과다.
 * 이걸 안 보면 <b>키를 잘못 넣었을 때도 200 을 받고</b>, 그 응답에는 items 가 없으므로
 * "이 주변에 장소가 없다" 로 해석된다. 그 상태로 캐시에 들어가면 <b>사용자가 있던 셀들이
 * 빈 지도로 굳는다.</b>
 *
 * <p>그래서 {@link Result} 가 성공·없음·실패 셋을 구분하고, <b>실패는 캐시하지 않는다.</b>
 *
 * <h2>키를 URL 에 조립하되 로그에 안 남긴다</h2>
 * <p>{@code TOUR.API.SECRET} 은 <b>이미 URL 인코딩된</b> 문자열이다(앱이 그렇게 써 왔다).
 * 기본 인코딩 모드로 넘기면 {@code %} 가 다시 {@code %25} 로 인코딩돼 인증이 조용히
 * 실패한다 — 그래서 빈이 {@code EncodingMode.NONE} 이고 쿼리스트링을 직접 만든다.
 *
 * <p><b>URL 을 로그에 찍지 않는다.</b> 찍는 순간 키가 로그에 남고, 로그는 우리가 통제하지
 * 못하는 곳으로 흘러간다(앱의 {@code LoggingClient} 가 같은 이유로 마스킹한다).
 * 남기는 것은 {@code resultCode} 와 사람이 읽는 메시지뿐이다.
 */
@Service
public class KtoApiClient {

    private static final Logger log = LoggerFactory.getLogger(KtoApiClient.class);

    /** KTO 가 "정상" 이라고 말하는 값. 그 밖은 전부 실패다. */
    private static final String RESULT_OK = "0000";

    /** 한도 초과. 이걸 보면 그 풀을 오늘치 닫는다. */
    static final String RESULT_QUOTA_EXCEEDED = "22";

    /** 서비스키 미등록. 키가 폐기됐거나 잘못 들어갔다는 뜻이라 계속 두드리면 안 된다. */
    static final String RESULT_KEY_NOT_REGISTERED = "30";

    /** 호출 전체의 상한. 소켓 타임아웃(5s)보다 길어야 그쪽이 먼저 걸린다. */
    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(6);

    /** 계약의 {@code PlaceCategory} 가 아는 KTO 콘텐츠타입. 그 밖은 category 를 생략한다. */
    private static final Set<String> KNOWN_CATEGORIES = Set.of("12", "14", "28", "32", "38", "39");

    private final WebClient petTour;
    private final WebClient serviceDetail;
    private final ObjectMapper objectMapper;
    private final String serviceKey;
    private final int numOfRows;

    public KtoApiClient(@Qualifier(KtoWebClientConfig.KOR_PET_TOUR) WebClient petTour,
                        @Qualifier(KtoWebClientConfig.KOR_SERVICE_DETAIL) WebClient serviceDetail,
                        ObjectMapper objectMapper,
                        @Value("${TOUR.API.SECRET}") String serviceKey,
                        @Value("${app.kto.num-of-rows:1000}") int numOfRows) {
        this.petTour = petTour;
        this.serviceDetail = serviceDetail;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey;
        this.numOfRows = numOfRows;
    }

    /**
     * 한 번의 KTO 호출 결과.
     *
     * <p>셋을 나누는 이유: <b>없음과 실패를 같게 다루면 안 된다.</b> 없음은 캐시해도 되고
     * (그 좌표에 정말 장소가 없다), 실패는 캐시하면 안 된다(다음에 다시 물어야 한다).
     */
    public sealed interface Result<T> {
        record Ok<T>(T value, int totalCount) implements Result<T> {}

        /** KTO 가 정상이라고 답했는데 내용이 없다. */
        record Empty<T>() implements Result<T> {}

        /** 호출이 안 됐거나 KTO 가 거절했다. {@code resultCode} 는 모를 수 있다. */
        record Failed<T>(String resultCode, String reason) implements Result<T> {}
    }

    /**
     * 셀 중심 주변의 반려동반 장소.
     *
     * <p>반경은 {@link GridCell#FETCH_RADIUS_M} 로 <b>고정</b>이다 — 사용자가 요청한 반경을
     * 쓰면 같은 셀이 반경마다 따로 캐시돼야 하고, 그러면 셀당 콜이 여러 배가 된다.
     * 넓게 한 번 받아 두고 좁혀서 주는 쪽이 예산을 아낀다.
     */
    public Result<List<PlaceDto>> fetchNearby(double centerLat, double centerLng) {
        String query = "serviceKey=" + serviceKey
                + "&MobileOS=ETC&MobileApp=heattrip&_type=json"
                + "&numOfRows=" + numOfRows + "&pageNo=1"
                + "&mapX=" + centerLng + "&mapY=" + centerLat
                + "&radius=" + GridCell.FETCH_RADIUS_M + "&arrange=E";

        return call(petTour, "/locationBasedList2?" + query, "nearby", body -> {
            List<PlaceDto> places = new ArrayList<>();
            for (JsonNode item : items(body)) {
                PlaceDto place = toPlace(item);
                if (place != null) {
                    places.add(place);
                }
            }
            return places;
        });
    }

    /** 장소 개요. {@code KorService2} 다 — 반려동반 서비스에는 이 오퍼레이션이 없다. */
    public Result<String> fetchOverview(String contentId) {
        String query = "serviceKey=" + serviceKey
                + "&MobileOS=ETC&MobileApp=heattrip&_type=json"
                + "&contentId=" + contentId;

        return call(serviceDetail, "/detailCommon2?" + query, "detailCommon", body -> {
            for (JsonNode item : items(body)) {
                String overview = text(item, "overview");
                return overview == null ? "" : overview;
            }
            return null;
        });
    }

    /** 반려동반 상세. 자유 텍스트 셋을 그대로 옮긴다. */
    public Result<PetInfoDto> fetchPetInfo(String contentId) {
        String query = "serviceKey=" + serviceKey
                + "&MobileOS=ETC&MobileApp=heattrip&_type=json"
                + "&contentId=" + contentId;

        return call(petTour, "/detailPetTour2?" + query, "detailPetTour", body -> {
            for (JsonNode item : items(body)) {
                return new PetInfoDto(
                        text(item, "acmpyPsblCpam"),
                        text(item, "acmpyNeedMtr"),
                        text(item, "etcAcmpyInfo"));
            }
            return null;
        });
    }

    // ─────────────────────────── 내부 ───────────────────────────

    private <T> Result<T> call(WebClient client, String pathAndQuery, String label,
                               java.util.function.Function<JsonNode, T> extract) {
        String raw;
        try {
            raw = client.get()
                    // 문자열 그대로 나간다 — 빈이 EncodingMode.NONE 이다. 키를 다시
                    // 인코딩하면 인증이 조용히 실패한다(KtoWebClientConfig javadoc).
                    .uri(pathAndQuery)
                    .retrieve()
                    .bodyToMono(String.class)
                    .timeout(CALL_TIMEOUT)
                    .block();
        } catch (RuntimeException e) {
            // 예외 메시지에 URL 이 섞일 수 있어 타입 이름만 남긴다 — URL 에는 키가 있다.
            log.warn("KTO 호출 실패 — op={} cause={}", label, e.getClass().getSimpleName());
            return new Result.Failed<>(null, e.getClass().getSimpleName());
        }

        if (raw == null || raw.isBlank()) {
            log.warn("KTO 응답이 비었다 — op={}", label);
            return new Result.Failed<>(null, "empty-body");
        }

        JsonNode body;
        try {
            body = objectMapper.readTree(raw);
        } catch (Exception e) {
            // KTO 는 오류를 XML 로 주는 경우가 있다. 그것도 실패다 — 캐시하지 않는다.
            log.warn("KTO 응답을 읽지 못했다 — op={} (JSON 이 아니다)", label);
            return new Result.Failed<>(null, "not-json");
        }

        String resultCode = body.path("response").path("header").path("resultCode").asText(null);
        if (resultCode == null || !RESULT_OK.equals(resultCode)) {
            String message = body.path("response").path("header").path("resultMsg").asText("");
            log.warn("KTO 가 거절했다 — op={} resultCode={} resultMsg={}", label, resultCode, message);
            return new Result.Failed<>(resultCode, message);
        }

        T value = extract.apply(body);
        if (value == null) {
            return new Result.Empty<>();
        }
        int totalCount = body.path("response").path("body").path("totalCount").asInt(0);
        return new Result.Ok<>(value, totalCount);
    }

    /**
     * {@code response.body.items.item} 을 배열로.
     *
     * <p>KTO 는 결과가 없으면 {@code items} 를 <b>빈 문자열</b>로 주고, 하나면 배열이 아니라
     * 객체로 준다. 둘 다 여기서 흡수한다 — 앱의 {@code PetPlacesRepository._parse} 가 이미
     * 같은 방어를 하고 있었고, 그 지식이 프록시로 옮겨 온 것이다.
     */
    private static List<JsonNode> items(JsonNode body) {
        JsonNode items = body.path("response").path("body").path("items");
        if (!items.isObject()) {
            return List.of();
        }
        JsonNode item = items.path("item");
        if (item.isArray()) {
            List<JsonNode> out = new ArrayList<>(item.size());
            item.forEach(out::add);
            return out;
        }
        return item.isObject() ? List.of(item) : List.of();
    }

    /**
     * KTO 항목 하나를 계약의 {@code Place} 로.
     *
     * <p>좌표가 없으면 {@code null} 을 준다 — 지도에 못 찍는 장소를 목록에 실으면 앱이
     * 0,0 에 마커를 그린다(앱이 이미 그 필터를 갖고 있었다).
     */
    private static PlaceDto toPlace(JsonNode item) {
        Double lat = number(item, "mapy");
        Double lng = number(item, "mapx");
        if (lat == null || lng == null || lat == 0 || lng == 0) {
            return null;
        }

        String contentTypeId = text(item, "contenttypeid");
        String image = text(item, "firstimage");
        if (image == null || image.isBlank()) {
            image = text(item, "firstimage2");
        }

        return new PlaceDto(
                text(item, "contentid"),
                nullToEmpty(text(item, "title")),
                PlaceDto.SOURCE_KTO,
                // 계약의 닫힌 enum 밖이면 생략한다 — 위 KNOWN_CATEGORIES javadoc 참조.
                contentTypeId != null && KNOWN_CATEGORIES.contains(contentTypeId) ? contentTypeId : null,
                contentTypeId,
                lat,
                lng,
                // 앱이 지금까지 addr1 만 썼다. addr2 를 붙이면 화면의 줄바꿈이 달라진다 —
                // 이 이슈는 호출 경로를 옮기는 것이지 표시를 바꾸는 것이 아니다.
                nullToEmpty(text(item, "addr1")),
                text(item, "tel"),
                image,
                null);
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String asText = value.asText();
        return asText.isBlank() ? null : asText;
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private static Double number(JsonNode node, String field) {
        String raw = text(node, field);
        if (raw == null) {
            return null;
        }
        try {
            return Double.parseDouble(raw);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}

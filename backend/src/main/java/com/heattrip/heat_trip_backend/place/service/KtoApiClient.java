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

    /**
     * 한도 초과. 이걸 보면 그 풀을 오늘치 닫는다.
     *
     * <p>HTTP 200 의 {@code resultCode} 로도, 4xx 의 {@code returnReasonCode} 로도 온다.
     * 두 봉투를 다 읽는 이유가 그것이다.
     */
    static final String RESULT_QUOTA_EXCEEDED = "22";

    /**
     * 서비스키 미등록. 키가 폐기됐거나 잘못 들어갔다는 뜻이라 계속 두드리면 안 된다.
     *
     * <p><b>실측(2026-09-01)</b>: 죽은 키로 부르면 HTTP <b>403</b> 과 함께
     * {@code {"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"returnReasonCode":"30", ...}}}} 가
     * 온다 — {@code response.header.resultCode} 가 아니다. 처음에 그쪽만 읽어서 이 판정이
     * 안 걸렸고, 그 상태로는 <b>죽은 키가 하루 예산을 전부 태운다.</b>
     */
    static final String RESULT_KEY_NOT_REGISTERED = "30";

    /** 호출 전체의 상한. 소켓 타임아웃(5s)보다 길어야 그쪽이 먼저 걸린다. */
    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(6);

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

    /**
     * <b>전국 반려동반 장소 한 페이지</b> — 이슈 #273.
     *
     * <h2>왜 좌표를 안 받는 길이 필요한가</h2>
     * <p>{@link #fetchNearby} 는 좌표를 받는다. A안 빌드(완전 온디바이스)는 좌표를 서버로
     * 안 보내므로 그 길을 못 쓴다 — 그러면 지도의 장소 목록이 빈다.
     *
     * <p>이 오퍼레이션은 <b>아무 지역 필터도 안 건다.</b> 요청에 좌표도 지역 코드도 없다.
     * 앱은 한 벌을 받아 기기에 두고, 거리 정렬을 기기에서 한다.
     *
     * <h2>왜 시군구로 안 쪼개는가 (실측 2026-09-04)</h2>
     * <p>전국이 <b>9,684곳</b>이고 우리 {@code Place} 계약 모양으로 직렬화하면 2.83MB,
     * <b>gzip 0.44MB</b> 다. 쪼개서 아끼는 것이 그 정도인데, 쪼개면 요청에 시군구가 실리고
     * (행정구역이지만 0 은 아니다) 한 벌 데우는 콜이 10 에서 249 로 는다.
     *
     * <h2>{@code areaCode} 를 안 쓰는 이유</h2>
     * <p>반려동반 데이터의 {@code areacode}·{@code sigungucode} 는 <b>빈 문자열</b>이다.
     * 살아 있는 것은 {@code lDongRegnCd}·{@code lDongSignguCd}(법정동) 쪽이다.
     * {@code areaCode=1}(서울)로 물으면 3,170곳이 아니라 <b>52곳</b>이 오고,
     * {@code sigunguCode} 까지 붙이면 <b>0곳</b>이 온다 — 실측이다.
     *
     * <p>그 값이 그대로 캐시에 들어가면 <b>200 으로 조용히 빈 지도</b>가 된다.
     * 지금은 필터를 아예 안 걸어서 그 함정 자체가 없다.
     *
     * @param pageNo 1부터. {@code totalCount} 를 넘어서면 빈 목록이 온다
     */
    public Result<List<PlaceDto>> fetchCatalogPage(int pageNo) {
        String query = "serviceKey=" + serviceKey
                + "&MobileOS=ETC&MobileApp=heattrip&_type=json"
                + "&numOfRows=" + numOfRows + "&pageNo=" + pageNo
                + "&arrange=A";

        return call(petTour, "/areaBasedList2?" + query, "catalog", body -> {
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
                    // exchangeToMono 인 이유: retrieve() 는 4xx/5xx 에서 예외를 던지며
                    // **본문을 버린다.** 그런데 KTO 는 키가 죽었을 때 그 사실을 403 **본문**에만
                    // 담아 준다(OpenAPI_ServiceResponse.cmmMsgHeader.returnReasonCode=30).
                    // 본문을 못 읽으면 "그냥 실패" 로만 보이고, 그러면 아래의 "풀을 즉시 닫는다"
                    // 가 영영 안 걸려 죽은 키로 하루 예산을 전부 태운다. (실측으로 찾았다)
                    .exchangeToMono(response -> response.bodyToMono(String.class)
                            .defaultIfEmpty(""))
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

        // KTO 의 오류 봉투는 **두 가지**다.
        //  ① 정상 경로의 실패 — HTTP 200 + response.header.resultCode
        //  ② 게이트웨이 단계의 실패 — HTTP 4xx + OpenAPI_ServiceResponse.cmmMsgHeader
        //     (키 미등록·트래픽 초과가 여기로 온다. 실측: 죽은 키 → 403 + returnReasonCode=30)
        // ②를 안 읽으면 "그냥 실패" 로만 보이고 풀을 닫는 판정이 영영 안 걸린다.
        JsonNode gatewayError = body.path("OpenAPI_ServiceResponse").path("cmmMsgHeader");
        if (!gatewayError.isMissingNode()) {
            String code = gatewayError.path("returnReasonCode").asText(null);
            String message = gatewayError.path("returnAuthMsg").asText("");
            log.warn("KTO 게이트웨이가 거절했다 — op={} returnReasonCode={} msg={}", label, code, message);
            return new Result.Failed<>(code, message);
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
     *
     * <p><b>{@code contentid} 가 없어도 같다.</b> 그 값이 상세로 들어가는 유일한 열쇠라
     * (경로가 {@code /api/places/{contentId}} 다) 없으면 목록에 떠도 누를 수 없는 줄이다.
     * 게다가 {@code PlaceDto} 는 {@code @JsonInclude(NON_NULL)} 이라 그런 항목은 키가
     * <b>통째로 빠진 채</b> 나가서, 계약이 {@code contentId} 를 {@code required} 로 선언한
     * 순간 그대로 위반이 된다 — 이슈 #24(ADR-0017 규약 1). 옆의 {@code title}·{@code addr1}
     * 은 {@code nullToEmpty} 로 감쌌으면서 이것만 안 감싸고 있었다.
     *
     * <p>패키지 안까지만 여는 것은 <b>테스트가 이 판정을 직접 볼 수 있게</b> 하기 위해서다.
     * 위의 {@code RESULT_*} 상수와 같은 이유다 — 통합 테스트의 가짜 KTO 는
     * {@link #fetchNearby} 를 통째로 갈아 끼우므로 이 매핑을 한 줄도 지나지 않는다.
     */
    static PlaceDto toPlace(JsonNode item) {
        Double lat = number(item, "mapy");
        Double lng = number(item, "mapx");
        if (lat == null || lng == null || lat == 0 || lng == 0) {
            return null;
        }

        String contentId = text(item, "contentid");
        if (contentId == null) {
            return null;
        }

        String contentTypeId = text(item, "contenttypeid");
        String image = text(item, "firstimage");
        if (image == null || image.isBlank()) {
            image = text(item, "firstimage2");
        }

        return new PlaceDto(
                contentId,
                nullToEmpty(text(item, "title")),
                PlaceDto.SOURCE_KTO,
                // 계약의 닫힌 enum 밖이면 생략한다 — PlaceDto.KNOWN_CATEGORIES javadoc 참조.
                contentTypeId != null && PlaceDto.KNOWN_CATEGORIES.contains(contentTypeId)
                        ? contentTypeId : null,
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

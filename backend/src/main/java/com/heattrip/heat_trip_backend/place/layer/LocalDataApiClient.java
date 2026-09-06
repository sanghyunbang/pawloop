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
import java.util.List;

/**
 * 행정안전부 인허가 데이터 호출 — 이슈 #291. 동물병원·동물판매업 <b>전국</b>.
 *
 * <h2>어디를 부르나</h2>
 * <p>공공데이터포털 게이트웨이 {@code https://apis.data.go.kr/1741000/{업종}/info}.
 * 서비스키는 KTO 와 <b>같은 키</b>다({@code TOUR.API.SECRET}) — 공공데이터포털의 인증키는
 * 계정 하나에 하나이고, API 마다 "활용신청" 을 눌러 열어 둬야 한다. 안 열려 있으면
 * 게이트웨이가 {@code returnReasonCode=30}(키 미등록) 을 준다. <b>그 응답을 받으면 그날은
 * 더 두드리지 않는다</b> — {@link LayerCatalogService} 가 예산 풀을 닫는다.
 *
 * <h2>영업 중만 받는다</h2>
 * <p>{@code cond[SALS_STTS_CD::EQ]=01} — 영업상태코드 01 이 "영업/정상" 이다. 전체를 받아
 * 걸러도 되지만, 폐업까지 받으면 페이지가 두 배다(동물병원 9,445 중 절반 가까이가 폐업).
 *
 * <h2>한 페이지 100</h2>
 * <p>명세가 {@code numOfRows} 상한을 100 으로 적는다. 영업 중인 동물병원 약 5,000 곳이면
 * 50 페이지, 판매업도 비슷하다 — 합쳐 하루 100 콜 남짓이고 일 한도는 10,000 이다.
 *
 * <p>키는 URL 에 조립하되 로그에 남기지 않는다 — {@code KtoApiClient} 와 같은 규칙이다.
 */
@Service
public class LocalDataApiClient {

    private static final Logger log = LoggerFactory.getLogger(LocalDataApiClient.class);

    /** 영업상태코드 "영업/정상". */
    static final String OPEN_STATUS_CODE = "01";

    private static final Duration CALL_TIMEOUT = Duration.ofSeconds(12);

    private final WebClient client;
    private final ObjectMapper objectMapper;
    private final String serviceKey;
    private final LayerCatalogProperties properties;

    public LocalDataApiClient(@Qualifier(KtoWebClientConfig.LOCALDATA) WebClient client,
                              ObjectMapper objectMapper,
                              @Value("${TOUR.API.SECRET}") String serviceKey,
                              LayerCatalogProperties properties) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey;
        this.properties = properties;
    }

    /**
     * 업종 하나의 한 페이지. 항목은 원본 JSON 그대로다 — 계약 모양으로 옮기는 일은
     * {@link LocalDataPlaceMapper} 가 한다.
     */
    public KtoApiClient.Result<List<JsonNode>> fetchPage(LocalDataBiz biz, int pageNo) {
        // cond[...] 의 대괄호와 콜론은 손으로 인코딩한다. 빈이 EncodingMode.NONE 이라
        // (키가 이미 인코딩돼 있어서) 여기서 안 하면 원문 그대로 나간다.
        String query = "serviceKey=" + serviceKey
                + "&pageNo=" + pageNo
                + "&numOfRows=" + properties.getLocaldataPageSize()
                + "&returnType=json"
                + "&cond%5BSALS_STTS_CD%3A%3AEQ%5D=" + OPEN_STATUS_CODE;

        String raw;
        try {
            raw = client.get()
                    .uri(biz.path() + "?" + query)
                    .exchangeToMono(response -> response.bodyToMono(String.class).defaultIfEmpty(""))
                    .timeout(CALL_TIMEOUT)
                    .block();
        } catch (RuntimeException e) {
            // 예외 메시지에 URL(=키)이 섞일 수 있어 타입 이름만 남긴다.
            log.warn("인허가 호출 실패 — biz={} page={} cause={}", biz, pageNo, e.getClass().getSimpleName());
            return new KtoApiClient.Result.Failed<>(null, e.getClass().getSimpleName());
        }

        if (raw == null || raw.isBlank()) {
            return new KtoApiClient.Result.Failed<>(null, "empty-body");
        }

        DataGoKrEnvelope.Parsed parsed;
        try {
            parsed = DataGoKrEnvelope.parse(objectMapper, raw);
        } catch (Exception e) {
            log.warn("인허가 응답을 읽지 못했다 — biz={} page={} ({})", biz, pageNo, e.getClass().getSimpleName());
            return new KtoApiClient.Result.Failed<>(null, "unreadable-body");
        }

        if (parsed.gatewayRejected()) {
            log.warn("공공데이터포털 게이트웨이가 거절했다 — biz={} returnReasonCode={} msg={}",
                    biz, parsed.gatewayError(), parsed.gatewayMessage());
            return new KtoApiClient.Result.Failed<>(parsed.gatewayError(), parsed.gatewayMessage());
        }

        if (!parsed.hasBody()) {
            log.warn("인허가 응답에 body 가 없다 — biz={} resultCode={} resultMsg={}",
                    biz, parsed.resultCode(), parsed.resultMsg());
            return new KtoApiClient.Result.Failed<>(parsed.resultCode(), parsed.resultMsg());
        }

        if (parsed.resultCode() != null && !DataGoKrEnvelope.OK_CODES.contains(parsed.resultCode())) {
            // 정상 코드가 명세와 다를 수 있다. body 는 왔으므로 실패로 치지 않되, 한 줄 남긴다 —
            // 실측 뒤 OK_CODES 를 맞추는 근거가 이 줄이다.
            log.info("인허가 resultCode={} (msg={}) — body 가 있어 계속한다", parsed.resultCode(), parsed.resultMsg());
        }

        if (parsed.items().isEmpty()) {
            return new KtoApiClient.Result.Empty<>();
        }
        return new KtoApiClient.Result.Ok<>(parsed.items(), parsed.totalCount());
    }
}

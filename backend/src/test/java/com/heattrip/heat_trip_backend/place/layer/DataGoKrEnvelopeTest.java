package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** 공공데이터포털 봉투 셋(JSON · 게이트웨이 거절 · XML)을 같은 모양으로 읽는다 — 이슈 #291. */
class DataGoKrEnvelopeTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    @DisplayName("정상 JSON — item 이 배열이면 그대로, 객체면 하나짜리 목록")
    void readsItemsFromJson() throws Exception {
        DataGoKrEnvelope.Parsed many = DataGoKrEnvelope.parse(MAPPER, """
                {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE"},
                 "body":{"items":{"item":[{"MNG_NO":"1"},{"MNG_NO":"2"}]},"totalCount":2,"pageNo":1,"numOfRows":100}}}
                """);
        assertThat(many.gatewayRejected()).isFalse();
        assertThat(many.resultCode()).isEqualTo("00");
        assertThat(many.items()).hasSize(2);
        assertThat(many.totalCount()).isEqualTo(2);
        assertThat(many.hasBody()).isTrue();

        DataGoKrEnvelope.Parsed one = DataGoKrEnvelope.parse(MAPPER, """
                {"response":{"header":{"resultCode":"0000"},"body":{"items":{"item":{"crsIdx":"A"}},"totalCount":1}}}
                """);
        assertThat(one.items()).hasSize(1);
        assertThat(one.items().get(0).path("crsIdx").asText()).isEqualTo("A");
    }

    @Test
    @DisplayName("items 가 빈 문자열이면 0건이다 — KTO 가 그렇게 준다")
    void emptyItemsStringMeansNoItems() throws Exception {
        DataGoKrEnvelope.Parsed parsed = DataGoKrEnvelope.parse(MAPPER, """
                {"response":{"header":{"resultCode":"0000"},"body":{"items":"","totalCount":0}}}
                """);
        assertThat(parsed.items()).isEmpty();
        assertThat(parsed.hasBody()).isTrue();
    }

    @Test
    @DisplayName("게이트웨이 거절(키 미등록 30)은 returnReasonCode 로 온다 — 2026-09-06 실측 그대로")
    void readsAGatewayRejection() throws Exception {
        DataGoKrEnvelope.Parsed parsed = DataGoKrEnvelope.parse(MAPPER, """
                {"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"errMsg":"SERVICE_KEY_IS_NOT_REGISTERED_ERROR",
                 "returnAuthMsg":"등록되지 않은 서비스키","returnReasonCode":"30"}}}
                """);
        assertThat(parsed.gatewayRejected()).isTrue();
        assertThat(parsed.gatewayError()).isEqualTo("30");
        assertThat(parsed.items()).isEmpty();
    }

    @Test
    @DisplayName("XML 로 오면 같은 트리로 눕힌다 — 반복 태그는 배열")
    void readsXmlTheSameWay() throws Exception {
        DataGoKrEnvelope.Parsed parsed = DataGoKrEnvelope.parse(MAPPER, """
                <?xml version="1.0" encoding="UTF-8"?>
                <response><header><resultCode>0000</resultCode><resultMsg>OK</resultMsg></header>
                <body><items><item><crsIdx>A</crsIdx><crsKorNm>가</crsKorNm></item>
                <item><crsIdx>B</crsIdx><crsKorNm>나</crsKorNm></item></items>
                <numOfRows>100</numOfRows><pageNo>1</pageNo><totalCount>2</totalCount></body></response>
                """);
        assertThat(parsed.resultCode()).isEqualTo("0000");
        assertThat(parsed.items()).hasSize(2);
        assertThat(parsed.items().get(1).path("crsKorNm").asText()).isEqualTo("나");
        assertThat(parsed.totalCount()).isEqualTo(2);
    }

    @Test
    @DisplayName("XML 게이트웨이 거절도 읽는다")
    void readsAnXmlGatewayRejection() throws Exception {
        DataGoKrEnvelope.Parsed parsed = DataGoKrEnvelope.parse(MAPPER, """
                <OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS_ERROR</errMsg>
                <returnAuthMsg>한도 초과</returnAuthMsg><returnReasonCode>22</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>
                """);
        assertThat(parsed.gatewayRejected()).isTrue();
        assertThat(parsed.gatewayError()).isEqualTo("22");
    }
}

package com.heattrip.heat_trip_backend.walksafety;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.walksafety.service.KmaGrid;
import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyParserTestAccess;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** 격자 역변환과 공공데이터 응답 읽기 — 순수 함수 (#336). */
class WalkSafetyParserTest {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    @DisplayName("격자 (60,127) 의 중심은 서울시청 근처다 — 앱의 순변환과 같은 상수")
    void gridCenterOfSeoulCityHall() {
        double[] c = KmaGrid.toLatLng(60, 127);
        assertThat(c[0]).isBetween(37.53, 37.60);
        assertThat(c[1]).isBetween(126.94, 127.01);
    }

    @Test
    @DisplayName("격자 범위 — nx 1~149 · ny 1~253")
    void gridRange() {
        assertThat(KmaGrid.isValid(61, 126)).isTrue();
        assertThat(KmaGrid.isValid(0, 126)).isFalse();
        assertThat(KmaGrid.isValid(150, 126)).isFalse();
        assertThat(KmaGrid.isValid(61, 254)).isFalse();
    }

    @Test
    @DisplayName("초단기실황 — 실제 응답 모양(2026-09-07 서울)에서 기온·습도·강수·PTY")
    void nowcastFromRealShape() {
        String raw = """
            {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL_SERVICE"},
             "body":{"items":{"item":[
               {"category":"PTY","obsrValue":"0"},{"category":"REH","obsrValue":"49"},
               {"category":"RN1","obsrValue":"0"},{"category":"T1H","obsrValue":"26.2"},
               {"category":"WSD","obsrValue":"3.2"}]}}}}
            """;
        var parsed = WalkSafetyParserTestAccess.nowcast(MAPPER, raw).orElseThrow();
        assertThat(parsed.tempC()).isEqualTo(26.2);
        assertThat(parsed.humidity()).isEqualTo(49);
        assertThat(parsed.rain1hMm()).isEqualTo(0.0);
        assertThat(parsed.precipType()).isEqualTo(0);
    }

    @Test
    @DisplayName("게이트웨이 오류(등록되지 않은 키)·서비스 오류·XML·기온 없음은 전부 없음 — 반쪽으로 답하지 않는다")
    void nowcastFailures() {
        String keyError = """
            {"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"errMsg":"SERVICE_KEY_IS_NOT_REGISTERED_ERROR","returnReasonCode":"30"}}}
            """;
        String serviceError = """
            {"response":{"header":{"resultCode":"03","resultMsg":"NO_DATA"},"body":{}}}
            """;
        String noTemp = """
            {"response":{"header":{"resultCode":"00"},"body":{"items":{"item":[{"category":"REH","obsrValue":"49"}]}}}}
            """;
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, keyError)).isEmpty();
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, serviceError)).isEmpty();
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, noTemp)).isEmpty();
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, "<OpenAPI_ServiceResponse/>")).isEmpty();
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, "{not json")).isEmpty();
        assertThat(WalkSafetyParserTestAccess.nowcast(MAPPER, "")).isEmpty();
    }

    @Test
    @DisplayName("측정소 목록 — dmX 가 위도, dmY 가 경도. 좌표 없는 행은 뺀다. 오류 응답은 빈 목록")
    void stations() {
        String raw = """
            {"response":{"body":{"items":[
              {"stationName":"성수","dmX":"37.5449","dmY":"127.0436"},
              {"stationName":"중구","dmX":"37.5642","dmY":"126.9748"},
              {"stationName":"깨진곳","dmX":"","dmY":""}],"totalCount":3},"header":{"resultCode":"00"}}}
            """;
        List<?> list = WalkSafetyParserTestAccess.stations(MAPPER, raw);
        assertThat(list).hasSize(2);
        assertThat(WalkSafetyParserTestAccess.stations(MAPPER,
                "{\"OpenAPI_ServiceResponse\":{\"cmmMsgHeader\":{\"returnReasonCode\":\"30\"}}}")).isEmpty();
    }

    @Test
    @DisplayName("실시간 측정 — \"-\" 는 null, 첫 행만 본다")
    void airQuality() {
        String raw = """
            {"response":{"body":{"items":[
              {"stationName":"성수","dataTime":"2026-09-07 14:00","pm10Value":"31","pm25Value":"-"}]},
             "header":{"resultCode":"00"}}}
            """;
        var q = WalkSafetyParserTestAccess.airQuality(MAPPER, raw).orElseThrow();
        assertThat(q.pm10()).isEqualTo(31);
        assertThat(q.pm25()).isNull();
        Optional<?> none = WalkSafetyParserTestAccess.airQuality(MAPPER,
                "{\"response\":{\"body\":{\"items\":[]},\"header\":{\"resultCode\":\"00\"}}}");
        assertThat(none).isEmpty();
    }
}

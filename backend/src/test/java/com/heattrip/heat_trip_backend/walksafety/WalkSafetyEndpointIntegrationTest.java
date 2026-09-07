package com.heattrip.heat_trip_backend.walksafety;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.walksafety.service.AirKoreaClient;
import com.heattrip.heat_trip_backend.walksafety.service.KmaNowcastClient;
import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyParserTestAccess;
import com.heattrip.heat_trip_backend.walksafety.service.WalkSafetyService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /api/walk-safety/now} — 인증 없이, 격자 번호만으로, 기상청이 죽으면 503 (#336).
 *
 * <p>외부 둘(기상청·에어코리아)은 가짜다 — 진짜를 부르면 키·쿼터·시각에 묶여 테스트가 시간에 따라
 * 달라진다. 파서는 {@code WalkSafetyParserTest} 가 실제 응답 모양으로 따로 본다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class WalkSafetyEndpointIntegrationTest extends AbstractMySqlIntegrationTest {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final String SEOUL_NOWCAST = """
        {"response":{"header":{"resultCode":"00"},"body":{"items":{"item":[
          {"category":"T1H","obsrValue":"26.2"},{"category":"REH","obsrValue":"49"},
          {"category":"RN1","obsrValue":"0"},{"category":"PTY","obsrValue":"0"}]}}}}
        """;
    private static final String STATIONS = """
        {"response":{"header":{"resultCode":"00"},"body":{"items":[
          {"stationName":"성수","dmX":"37.5449","dmY":"127.0436"},
          {"stationName":"중구","dmX":"37.5642","dmY":"126.9748"}]}}}
        """;
    private static final String SEONGSU_AIR = """
        {"response":{"header":{"resultCode":"00"},"body":{"items":[
          {"stationName":"성수","dataTime":"2026-09-07 14:00","pm10Value":"31","pm25Value":"18"}]}}}
        """;

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private WalkSafetyService service;
    @MockitoBean
    private KmaNowcastClient kma;
    @MockitoBean
    private AirKoreaClient air;

    @BeforeEach
    void freshCaches() {
        service.clearCaches();
        when(kma.enabled()).thenReturn(true);
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString()))
                .thenReturn(WalkSafetyParserTestAccess.nowcast(MAPPER, SEOUL_NOWCAST));
        when(air.stations()).thenReturn(WalkSafetyParserTestAccess.stations(MAPPER, STATIONS));
        when(air.realtime(anyString())).thenReturn(WalkSafetyParserTestAccess.airQuality(MAPPER, SEONGSU_AIR));
    }

    @Test
    @DisplayName("인증 없이 격자 번호만으로 200 — 기온·습도·강수·미세먼지·측정소가 계약 키로 온다")
    void nowWithoutAuth() throws Exception {
        MvcResult result = mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "126"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tempC").value(26.2))
                .andExpect(jsonPath("$.humidity").value(49))
                .andExpect(jsonPath("$.precipType").value(0))
                .andExpect(jsonPath("$.pm10").value(31))
                .andExpect(jsonPath("$.pm25").value(18))
                .andExpect(jsonPath("$.station").value("성수"))
                .andReturn();
        JsonNode body = MAPPER.readTree(result.getResponse().getContentAsString());
        assertThat(body.fieldNames()).toIterable()
                .as("계약(openapi WalkSafetyNow)의 키 집합 — 앱 파서가 이 이름으로 읽는다")
                .containsExactlyInAnyOrder("tempC", "humidity", "rain1hMm", "precipType", "pm10", "pm25", "station", "observedAt");
        assertThat(result.getResponse().getHeader("Cache-Control")).contains("max-age=600");
        verify(air).realtime("성수");
    }

    @Test
    @DisplayName("같은 격자를 10분 안에 다시 물으면 기상청을 다시 부르지 않는다 — 격자 캐시")
    void secondCallHitsCache() throws Exception {
        mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "126")).andExpect(status().isOk());
        mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "126")).andExpect(status().isOk());

        verify(kma, times(1)).fetch(anyInt(), anyInt(), anyString(), anyString());
    }

    @Test
    @DisplayName("에어코리아가 승인 전(빈 목록)이면 PM 이 null 로 온다 — 기온만으로도 200 이다")
    void withoutAirKorea() throws Exception {
        when(air.stations()).thenReturn(List.of());

        mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "126"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tempC").value(26.2))
                .andExpect(jsonPath("$.pm25").value((Object) null))
                .andExpect(jsonPath("$.station").value((Object) null));
    }

    @Test
    @DisplayName("기상청 실황을 못 받으면 503 — 반쪽 값을 주지 않고, 앱은 카드를 그리지 않는다")
    void kmaDown() throws Exception {
        when(kma.fetch(anyInt(), anyInt(), anyString(), anyString())).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "126"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.error.code").exists());
    }

    @Test
    @DisplayName("격자 범위 밖이면 400 — 기상청을 부르지 않는다")
    void badGrid() throws Exception {
        mockMvc.perform(get("/api/walk-safety/now").param("nx", "0").param("ny", "126"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/walk-safety/now").param("nx", "61").param("ny", "999"))
                .andExpect(status().isBadRequest());

        verify(kma, times(0)).fetch(anyInt(), anyInt(), anyString(), anyString());
    }
}

package com.heattrip.heat_trip_backend.place;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.service.GridCell;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 관광공사 프록시의 HTTP 경로 — 이슈 #40 완료 조건 3 · 4.
 *
 * <h2>KTO 를 진짜로 부르지 않는다</h2>
 * <p>{@link KtoApiClient} 를 <b>가짜로 갈아끼운다.</b> 진짜를 부르면 테스트가 실행될 때마다
 * 하루 1,000콜 중 몇 개를 태우고, CI 에서 도는 순간 그날 운영이 죽는다.
 *
 * <p>여기서 재는 것은 KTO 가 아니라 <b>우리 쪽 규칙</b>이다 — 캐시가 두 번째 호출을 막는가,
 * 예산이 없으면 오래된 답을 주는가, 모르는 id 가 아웃바운드 없이 404 인가.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ContextConfiguration(classes = PlaceProxyIntegrationTest.StubbedKto.class)
class PlaceProxyIntegrationTest extends AbstractMySqlIntegrationTest {

    /** 서울시청 근처. 셀 하나 안에 있다. */
    private static final double LAT = 37.5665;
    private static final double LNG = 126.9780;

    @TestConfiguration
    static class StubbedKto {
        @Bean
        @Primary
        FakeKto fakeKto() {
            return new FakeKto();
        }
    }

    /**
     * 호출 수를 세는 가짜 KTO.
     *
     * <p>{@link KtoApiClient} 를 상속한다 — 인터페이스를 새로 파면 진짜 구현이 그 인터페이스를
     * 따르는지 아무도 안 보게 되고, 그러면 이 테스트가 실제 클라이언트와 갈라진다.
     */
    static class FakeKto extends KtoApiClient {
        final AtomicInteger nearbyCalls = new AtomicInteger();
        final AtomicInteger detailCalls = new AtomicInteger();
        /** 기본 응답. 테스트가 바꿔 놓은 것을 매번 여기로 되돌린다. */
        static final Result<List<PlaceDto>> DEFAULT_NEARBY = new Result.Ok<>(List.of(
                new PlaceDto("111", "서울숲", PlaceDto.SOURCE_KTO, "12", "12",
                        37.5445, 127.0374, "서울 성동구", "02-000-0000", null, null),
                new PlaceDto("222", "먼 곳", PlaceDto.SOURCE_KTO, "39", "39",
                        38.5000, 127.0000, "강원", null, null, null)), 2);

        final AtomicReference<Result<List<PlaceDto>>> nearbyResult =
                new AtomicReference<>(DEFAULT_NEARBY);

        FakeKto() {
            super(null, null, null, "unused", 1);
        }

        @Override
        public Result<List<PlaceDto>> fetchNearby(double centerLat, double centerLng) {
            nearbyCalls.incrementAndGet();
            return nearbyResult.get();
        }

        @Override
        public Result<String> fetchOverview(String contentId) {
            detailCalls.incrementAndGet();
            return new Result.Ok<>("개요입니다", 1);
        }

        @Override
        public Result<PetInfoDto> fetchPetInfo(String contentId) {
            detailCalls.incrementAndGet();
            return new Result.Ok<>(new PetInfoDto("소형견", "목줄 필수", null), 1);
        }
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private FakeKto kto;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void reset() {
        jdbc.update("delete from kto_call_budget");
        jdbc.update("delete from place_cell");
        jdbc.update("delete from pet_place_detail");
        kto.nearbyCalls.set(0);
        kto.detailCalls.set(0);
        // 실패 시나리오를 쓰는 테스트가 이 값을 바꿔 놓는다. 안 되돌리면 뒤 테스트가
        // 전부 빈 목록을 받고, 그 실패는 "왜인지 모르겠는" 모양으로 나온다.
        kto.nearbyResult.set(FakeKto.DEFAULT_NEARBY);
    }

    // ─────────────────────────── 완료 조건 3 · 4 ───────────────────────────

    @Test
    @DisplayName("인증 없이 부를 수 있고 계약의 Place 모양으로 답한다")
    void nearbyIsPublicAndMatchesTheContract() throws Exception {
        mockMvc.perform(get("/api/places/nearby").param("lat", String.valueOf(LAT))
                        .param("lng", String.valueOf(LNG)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].contentId").value("111"))
                .andExpect(jsonPath("$[0].title").value("서울숲"))
                .andExpect(jsonPath("$[0].source").value("kto"))
                .andExpect(jsonPath("$[0].category").value("12"))
                .andExpect(jsonPath("$[0].distM").isNumber());
    }

    @Test
    @DisplayName("같은 셀을 두 번 물어도 KTO 는 한 번만 부른다 — 이게 격자의 존재 이유다")
    void theSecondRequestInTheSameCellCostsNothing() throws Exception {
        callNearby(LAT, LNG);
        // 같은 셀 안의 다른 좌표. 앱은 5m 마다 위치를 갱신하므로 이런 요청이 계속 온다.
        callNearby(LAT + 0.001, LNG + 0.001);

        assertThat(kto.nearbyCalls.get())
                .as("""
                        좌표를 그대로 키로 쓰면 한 번의 산책이 수백 콜이 되고, 사용자 한 명이
                        하루 한도(1,000)를 태울 수 있다.
                        """)
                .isEqualTo(1);
    }

    @Test
    @DisplayName("반경 밖의 장소는 빠진다 — 스냅샷은 20km 를 담지만 답은 요청한 반경이다")
    void placesOutsideTheRequestedRadiusAreDropped() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", String.valueOf(LAT)).param("lng", String.valueOf(LNG))
                        .param("radius", "8000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].contentId").value("111"));
    }

    @Test
    @DisplayName("반경을 크게 보내도 거절하지 않고 자른다 — 지도를 죽이는 것보다 낫다")
    void anOversizedRadiusIsClampedNotRejected() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", String.valueOf(LAT)).param("lng", String.valueOf(LNG))
                        .param("radius", "999999"))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("좌표가 범위를 벗어나면 400 이다")
    void badCoordinatesAreRejected() throws Exception {
        mockMvc.perform(get("/api/places/nearby").param("lat", "91").param("lng", "0"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("미구현 레이어는 KTO 를 안 부르고 빈 목록이다 — 부르면 예산만 태운다")
    void unimplementedLayersCostNothing() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", String.valueOf(LAT)).param("lng", String.valueOf(LNG))
                        .param("category", "vet"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));

        assertThat(kto.nearbyCalls.get()).isZero();
    }

    @Test
    @DisplayName("예산이 없으면 오래된 스냅샷을 그대로 준다 — 빈 지도보다 낫다")
    void anExhaustedBudgetStillServesTheOldSnapshot() throws Exception {
        callNearby(LAT, LNG);

        // 스냅샷을 낡게 만들고 예산을 소진시킨다.
        jdbc.update("update place_cell set fetched_at = fetched_at - interval 10 day");
        jdbc.update("update kto_call_budget set used = 999999 where pool = 'nearby'");
        int before = kto.nearbyCalls.get();

        mockMvc.perform(get("/api/places/nearby").param("lat", String.valueOf(LAT))
                        .param("lng", String.valueOf(LNG)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].contentId").value("111"));

        assertThat(kto.nearbyCalls.get())
                .as("만료를 두면 여기서 셀이 사라지고 지도가 영구히 빈 화면이 된다")
                .isEqualTo(before);
    }

    @Test
    @DisplayName("KTO 가 실패하면 스냅샷을 안 덮어쓴다 — 실패를 캐시하면 셀이 빈 지도로 굳는다")
    void aFailureDoesNotOverwriteWhatWeHave() throws Exception {
        callNearby(LAT, LNG);
        jdbc.update("update place_cell set fetched_at = fetched_at - interval 10 day");
        kto.nearbyResult.set(new KtoApiClient.Result.Failed<>("22", "한도초과"));

        mockMvc.perform(get("/api/places/nearby").param("lat", String.valueOf(LAT))
                        .param("lng", String.valueOf(LNG)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].contentId").value("111"));
    }

    @Test
    @DisplayName("키가 죽으면 그 풀이 닫힌다 — 게이트웨이는 403 과 다른 봉투로 답한다")
    void aDeadKeyClosesThePool() throws Exception {
        // 실측(2026-09-01): 죽은 키로 부르면 HTTP 403 과 함께
        //   {"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"returnReasonCode":"30", ...}}}
        // 가 온다. response.header.resultCode 만 읽던 동안에는 이 판정이 안 걸렸고,
        // 그러면 죽은 키가 셀마다 1콜씩 하루 예산을 전부 태운다.
        kto.nearbyResult.set(new KtoApiClient.Result.Failed<>("30", "등록되지 않은 서비스키"));

        callNearby(LAT, LNG);

        Integer used = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'nearby'", Integer.class);
        assertThat(used)
                .as("풀이 닫혀야 더 이상 안 두드린다. 계속 두드리면 차단당한다")
                .isNotNull()
                .isGreaterThanOrEqualTo(300);
    }

    @Test
    @DisplayName("KTO 가 한도 초과라고 하면 그 풀이 닫힌다 — 계속 두드리면 차단당한다")
    void quotaExceededClosesThePool() throws Exception {
        callNearby(LAT, LNG);
        jdbc.update("update place_cell set fetched_at = fetched_at - interval 10 day, "
                + "failed_at = null, fail_streak = 0");
        kto.nearbyResult.set(new KtoApiClient.Result.Failed<>("22", "한도초과"));

        callNearby(LAT, LNG);

        Integer used = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'nearby'", Integer.class);
        assertThat(used).isNotNull().isGreaterThanOrEqualTo(300);
    }

    // ─────────────────────────── 상세 ───────────────────────────

    @Test
    @DisplayName("목록에 실어 보낸 장소는 상세를 받을 수 있다")
    void aKnownPlaceHasDetail() throws Exception {
        callNearby(LAT, LNG);

        mockMvc.perform(get("/api/places/{id}", "111"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.contentId").value("111"))
                .andExpect(jsonPath("$.title").value("서울숲"))
                .andExpect(jsonPath("$.overview").value("개요입니다"))
                .andExpect(jsonPath("$.petInfo.acmpyPsblCpam").value("소형견"))
                .andExpect(jsonPath("$.petInfo.etcAcmpyInfo").doesNotExist());
    }

    @Test
    @DisplayName("모르는 contentId 는 아웃바운드 0콜로 404 다 — 이게 없으면 예산이 털린다")
    void anUnknownIdCostsNothing() throws Exception {
        mockMvc.perform(get("/api/places/{id}", "99999999"))
                .andExpect(status().isNotFound());

        assertThat(kto.detailCalls.get())
                .as("상세 1건이 2콜이라 75번이면 하루치다. 허용목록이 그 경로를 닫는다")
                .isZero();
    }

    @Test
    @DisplayName("상세를 두 번 물어도 KTO 는 한 번만 부른다 — 30일 캐시다")
    void theSecondDetailRequestCostsNothing() throws Exception {
        callNearby(LAT, LNG);
        mockMvc.perform(get("/api/places/{id}", "111")).andExpect(status().isOk());
        int after = kto.detailCalls.get();

        mockMvc.perform(get("/api/places/{id}", "111")).andExpect(status().isOk());

        assertThat(kto.detailCalls.get()).isEqualTo(after);
    }

    @Test
    @DisplayName("상세 1건이 2콜이라 예산도 2 를 쓴다")
    void oneDetailBurnsTwoUnits() throws Exception {
        callNearby(LAT, LNG);

        mockMvc.perform(get("/api/places/{id}", "111")).andExpect(status().isOk());

        Integer used = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'detail'", Integer.class);
        assertThat(used).isEqualTo(2);
        assertThat(kto.detailCalls.get()).isEqualTo(2);
    }

    @Test
    @DisplayName("상세에는 distM 이 없다 — 기준점이 없기 때문이다")
    void detailCarriesNoDistance() throws Exception {
        callNearby(LAT, LNG);

        mockMvc.perform(get("/api/places/{id}", "111"))
                .andExpect(jsonPath("$.distM").doesNotExist());
    }

    @Test
    @DisplayName("계약이 정한 반경 상한이 격자가 보장하는 값 이하다")
    void theContractRadiusFitsWhatTheGridGuarantees() {
        assertThat(18_000)
                .as("계약의 maximum 이다. 넘으면 서버가 200 으로 덜 덮인 답을 준다")
                .isLessThanOrEqualTo(GridCell.GUARANTEED_RADIUS_M);
    }

    private void callNearby(double lat, double lng) throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", String.valueOf(lat)).param("lng", String.valueOf(lng))
                        .param("radius", "18000"))
                .andExpect(status().isOk());
    }
}

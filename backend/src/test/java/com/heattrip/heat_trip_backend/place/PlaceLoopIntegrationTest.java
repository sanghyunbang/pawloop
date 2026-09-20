package com.heattrip.heat_trip_backend.place;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.entity.PetPlaceDetailRow;
import com.heattrip.heat_trip_backend.place.repository.PetPlaceDetailRepository;
import com.heattrip.heat_trip_backend.place.repository.TrailRouteRepository;
import com.heattrip.heat_trip_backend.place.service.OrsRoutingClient;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.service.CatalogSnapshotStore;
import com.heattrip.heat_trip_backend.place.service.PlaceLoopService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 코스 추천 왕복 경로의 실측 — 이슈 #725. ORS 는 가짜다(하루 한도 200 을 검사가 태우면 안 된다).
 *
 * <ul>
 *   <li>seed 셋을 받아 <b>가장 가까운</b> 것을 주고, 두 번째 요청은 <b>표에서</b> 온다(가짜가 더 안 불린다).</li>
 *   <li>모르는 장소는 404 — 바깥 호출 0. 허용목록에 없어도 레이어 한 벌(동네 길)에 있으면 아는 장소다.</li>
 *   <li>길이는 500 단위로 맞춘다.</li>
 *   <li>키 없음 · 예산 소진은 200 + {@code available=false}.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
class PlaceLoopIntegrationTest extends AbstractMySqlIntegrationTest {

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        FakeOrs fakeOrs() {
            return new FakeOrs();
        }
    }

    /** seed 마다 정해 둔 길이를 준다. 몇 번 불렸는지 센다. */
    static class FakeOrs implements OrsRoutingClient {
        volatile boolean configured = true;
        final Map<Integer, Double> distanceBySeed = new HashMap<>();
        final AtomicInteger calls = new AtomicInteger();

        void reset() {
            configured = true;
            calls.set(0);
            distanceBySeed.clear();
            distanceBySeed.put(1, 5478.0);
            distanceBySeed.put(2, 2130.0);
            distanceBySeed.put(3, 1600.0);
        }

        @Override
        public boolean isConfigured() {
            return configured;
        }

        @Override
        public Optional<Loop> roundTrip(double lat, double lng, int lengthM, int points, int seed) {
            calls.incrementAndGet();
            Double distance = distanceBySeed.get(seed);
            if (distance == null) {
                return Optional.empty();
            }
            return Optional.of(new Loop(distance, distance / 1.25, List.of(
                    new double[] {lng, lat}, new double[] {lng + 0.003, lat + 0.002}, new double[] {lng, lat})));
        }
    }

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private FakeOrs ors;
    @Autowired private PetPlaceDetailRepository details;
    @Autowired private TrailRouteRepository routes;
    @Autowired private KtoBudgetProperties budget;
    @Autowired private CatalogSnapshotStore snapshots;

    private String contentId;

    @BeforeEach
    void setUp() {
        ors.reset();
        contentId = "loop-" + System.nanoTime() + "-" + SEQUENCE.incrementAndGet();
        details.save(PetPlaceDetailRow.builder()
                .contentId(contentId)
                .title("서울숲")
                .addr("서울 성동구")
                .tel("")
                .image("")
                .lat(37.5443)
                .lng(127.0376)
                .contentTypeId("12")
                .build());
    }

    @Test
    @DisplayName("동네 길(trail:lt…)처럼 허용목록에 없어도 레이어 한 벌에 있으면 코스를 준다 — 2026-09-21 폰에서 전부 404 였다")
    void trailFromLayerIndex() throws Exception {
        String trailId = "trail:lt" + System.nanoTime();
        // 제주 바닷가 — 다른 검사가 넣어 둔 관광공사 항목과 같은 자리에 두면 겹침 정리(#411)에 빠진다.
        snapshots.store(CatalogSource.LOCALTRAIL, List.of(new PlaceDto(trailId, "3.1운동길B", "trail", "trail",
                null, 33.2461, 126.5653, "제주", "", "", null, null)), 1);

        JsonNode body = body(mockMvc.perform(get("/api/places/{id}/loop", trailId).param("lengthM", "2000"))
                .andExpect(status().isOk()).andReturn());

        assertThat(body.path("available").asBoolean()).as("허용목록만 보면 여기서 404 다").isTrue();
        assertThat(body.path("distanceM").asInt()).isEqualTo(2130);
        assertThat(body.path("points").get(0).get(1).asDouble()).as("출발점은 그 길의 좌표다").isEqualTo(33.2461);
        assertThat(ors.calls.get()).isEqualTo(3);
        assertThat(routes.findById(PlaceLoopService.courseIdOf(trailId, 2000))).isPresent();
    }

    @Test
    @DisplayName("seed 셋 중 가장 가까운 것을 주고, 두 번째 요청은 표에서 온다 — 가짜가 더 안 불린다")
    void picksClosestAndStores() throws Exception {
        JsonNode first = body(mockMvc.perform(get("/api/places/{id}/loop", contentId).param("lengthM", "2000"))
                .andExpect(status().isOk()).andReturn());

        assertThat(first.path("available").asBoolean()).isTrue();
        assertThat(first.path("targetM").asInt()).isEqualTo(2000);
        assertThat(first.path("distanceM").asInt()).as("5,478 · 2,130 · 1,600 중 2,130").isEqualTo(2130);
        assertThat(first.path("durationS").asInt()).isEqualTo(1704);
        assertThat(first.path("pointCount").asInt()).isEqualTo(3);
        assertThat(first.path("points").size()).isEqualTo(3);
        assertThat(first.path("points").get(0).get(0).asDouble()).isEqualTo(127.0376);
        assertThat(ors.calls.get()).as("seed 셋 = 바깥 호출 셋").isEqualTo(3);
        assertThat(routes.findById(PlaceLoopService.courseIdOf(contentId, 2000))).isPresent();

        JsonNode second = body(mockMvc.perform(get("/api/places/{id}/loop", contentId).param("lengthM", "2000"))
                .andExpect(status().isOk()).andReturn());
        assertThat(second.path("distanceM").asInt()).isEqualTo(2130);
        assertThat(ors.calls.get()).as("표에 있으면 바깥을 다시 안 부른다 — 하루 200 이 전부다").isEqualTo(3);
    }

    @Test
    @DisplayName("모르는 장소는 404 — 바깥 호출 0")
    void unknownPlaceIs404WithoutUpstream() throws Exception {
        mockMvc.perform(get("/api/places/{id}/loop", "no-such-place-" + contentId).param("lengthM", "2000"))
                .andExpect(status().isNotFound());
        assertThat(ors.calls.get()).isZero();
    }

    @Test
    @DisplayName("길이는 500 단위로 맞춘다 — 1,234 는 1,000, 12,000 은 10,000")
    void normalizesLength() throws Exception {
        assertThat(PlaceLoopService.normalizeLength(1234)).isEqualTo(1000);
        assertThat(PlaceLoopService.normalizeLength(1750)).isEqualTo(2000);
        assertThat(PlaceLoopService.normalizeLength(12000)).isEqualTo(10000);
        assertThat(PlaceLoopService.normalizeLength(10)).isEqualTo(500);

        ors.distanceBySeed.put(2, 1050.0);
        JsonNode body = body(mockMvc.perform(get("/api/places/{id}/loop", contentId).param("lengthM", "1234"))
                .andExpect(status().isOk()).andReturn());
        assertThat(body.path("targetM").asInt()).isEqualTo(1000);
        assertThat(body.path("distanceM").asInt()).isEqualTo(1050);
    }

    @Test
    @DisplayName("키가 없으면 200 에 available=false · nokey — 오류가 아니라 지금은 없음")
    void noKeyIsUnavailableNotAnError() throws Exception {
        ors.configured = false;
        JsonNode body = body(mockMvc.perform(get("/api/places/{id}/loop", contentId))
                .andExpect(status().isOk()).andReturn());

        assertThat(body.path("available").asBoolean()).isFalse();
        assertThat(body.path("reason").asText()).isEqualTo("nokey");
        assertThat(body.path("points").size()).isZero();
        assertThat(ors.calls.get()).isZero();
    }

    @Test
    @DisplayName("하루 예산이 다 떨어졌으면 바깥을 안 부르고 available=false · budget")
    void exhaustedBudgetIsUnavailable() throws Exception {
        int before = budget.getOrsLoopMaxCallsPerDay();
        budget.setOrsLoopMaxCallsPerDay(0);
        try {
            JsonNode body = body(mockMvc.perform(get("/api/places/{id}/loop", contentId))
                    .andExpect(status().isOk()).andReturn());
            assertThat(body.path("available").asBoolean()).isFalse();
            assertThat(body.path("reason").asText()).isEqualTo("budget");
            assertThat(ors.calls.get()).isZero();
        } finally {
            budget.setOrsLoopMaxCallsPerDay(before);
        }
    }

    @Test
    @DisplayName("전부 두 배 넘게 어긋나면 available=false · upstream — 틀린 코스보다 없는 편이 낫다")
    void wildlyOffCandidatesAreNotRecommended() throws Exception {
        ors.distanceBySeed.put(1, 5478.0);
        ors.distanceBySeed.put(2, 6000.0);
        ors.distanceBySeed.put(3, 4500.0);
        JsonNode body = body(mockMvc.perform(get("/api/places/{id}/loop", contentId).param("lengthM", "2000"))
                .andExpect(status().isOk()).andReturn());

        assertThat(body.path("available").asBoolean()).isFalse();
        assertThat(body.path("reason").asText()).isEqualTo("upstream");
        assertThat(routes.findById(PlaceLoopService.courseIdOf(contentId, 2000))).as("안 준 것은 저장하지 않는다").isEmpty();
    }

    private static JsonNode body(MvcResult result) throws Exception {
        return MAPPER.readTree(result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
    }
}

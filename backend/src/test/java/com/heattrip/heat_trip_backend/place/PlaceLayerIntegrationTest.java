package com.heattrip.heat_trip_backend.place;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;
import com.heattrip.heat_trip_backend.place.layer.DurunubiApiClient;
import com.heattrip.heat_trip_backend.place.layer.GpxFetcher;
import com.heattrip.heat_trip_backend.place.layer.LayerCatalogProperties;
import com.heattrip.heat_trip_backend.place.layer.LayerCatalogService;
import com.heattrip.heat_trip_backend.place.layer.LocalDataApiClient;
import com.heattrip.heat_trip_backend.place.layer.LocalDataBiz;
import com.heattrip.heat_trip_backend.place.repository.PlaceCatalogRepository;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;
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
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 동물병원·펫샵·산책로 레이어가 카탈로그에 이어 붙고, 주변 조회와 산책로 선 경로가 돈다 — 이슈 #291.
 *
 * <p>공공데이터 API 는 셋 다 가짜다 — 인허가 항목은 서울 열린데이터광장 sample 행의 TM 좌표
 * 그대로이고, 두루누비는 코스 하나에 GPX 다섯 점이다. 좌표 변환·이어 붙이기·ETag·예산·실패
 * 처리는 <b>진짜</b>가 돈다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ContextConfiguration(classes = PlaceLayerIntegrationTest.Fakes.class)
class PlaceLayerIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String CATALOG = "/api/places/catalog";
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        FakeKto fakeKto() {
            return new FakeKto();
        }

        @Bean
        @Primary
        FakeLocalData fakeLocalData(LayerCatalogProperties properties) {
            return new FakeLocalData(properties);
        }

        @Bean
        @Primary
        FakeDurunubi fakeDurunubi(LayerCatalogProperties properties) {
            return new FakeDurunubi(properties);
        }

        @Bean
        @Primary
        FakeGpx fakeGpx() {
            return new FakeGpx();
        }
    }

    /** KTO 두 곳. 셀 조회도 같은 둘을 준다. */
    static class FakeKto extends KtoApiClient {
        final AtomicInteger catalogCalls = new AtomicInteger();
        final AtomicInteger nearbyCalls = new AtomicInteger();
        final AtomicInteger totalPlaces = new AtomicInteger(2);

        FakeKto() {
            super(null, null, null, "unused", 1000);
        }

        private List<PlaceDto> places() {
            List<PlaceDto> out = new ArrayList<>();
            if (totalPlaces.get() >= 1) {
                out.add(new PlaceDto("100", "서울숲", PlaceDto.SOURCE_KTO, "12", "12",
                        37.5445, 127.0374, "서울 성동구", null, null, null));
            }
            if (totalPlaces.get() >= 2) {
                out.add(new PlaceDto("101", "논현동 카페", PlaceDto.SOURCE_KTO, "39", "39",
                        37.5100, 127.0300, "서울 강남구", null, null, null));
            }
            return out;
        }

        @Override
        public Result<List<PlaceDto>> fetchCatalogPage(int pageNo) {
            catalogCalls.incrementAndGet();
            if (pageNo > 1 || totalPlaces.get() == 0) {
                return new Result.Empty<>();
            }
            return new Result.Ok<>(places(), totalPlaces.get());
        }

        @Override
        public Result<List<PlaceDto>> fetchNearby(double centerLat, double centerLng) {
            nearbyCalls.incrementAndGet();
            return new Result.Ok<>(places(), places().size());
        }

        @Override
        public Result<String> fetchOverview(String contentId) {
            return new Result.Ok<>("개요", 1);
        }

        @Override
        public Result<PetInfoDto> fetchPetInfo(String contentId) {
            return new Result.Ok<>(new PetInfoDto(null, null, null), 1);
        }
    }

    /** 인허가 — 병원 하나(강남구 논현로 607) · 판매업 하나(강동구 올림픽로 783). TM 좌표 그대로. */
    static class FakeLocalData extends LocalDataApiClient {
        final AtomicInteger pageCalls = new AtomicInteger();
        final AtomicInteger failFromPage = new AtomicInteger(0);
        final AtomicReference<String> failCode = new AtomicReference<>("999");

        FakeLocalData(LayerCatalogProperties properties) {
            super(null, null, "unused", properties);
        }

        @Override
        public KtoApiClient.Result<List<JsonNode>> fetchPage(LocalDataBiz biz, int pageNo) {
            pageCalls.incrementAndGet();
            if (failFromPage.get() > 0 && pageNo >= failFromPage.get()) {
                return new KtoApiClient.Result.Failed<>(failCode.get(), "가짜 실패");
            }
            if (pageNo > 1) {
                return new KtoApiClient.Result.Empty<>();
            }
            String json = biz == LocalDataBiz.VET
                    ? """
                      {"MNG_NO":"322000001020260003","BPLC_NM":"늘서울피부과동물병원","SALS_STTS_CD":"01",
                       "CRD_INFO_X":"202875.328642756","CRD_INFO_Y":"445077.204272347",
                       "ROAD_NM_ADDR":"서울특별시 강남구 논현로 607","TELNO":"02-518-3650"}
                      """
                    : """
                      {"MNG_NO":"324000001120260020","BPLC_NM":"준온누리약국","SALS_STTS_CD":"01",
                       "CRD_INFO_X":"211205.932552687","CRD_INFO_Y":"449882.950636731",
                       "ROAD_NM_ADDR":"서울특별시 강동구 올림픽로 783","DTL_TASK_SE_NM":"동물판매업"}
                      """;
            try {
                return new KtoApiClient.Result.Ok<>(List.of(MAPPER.readTree(json)), 1);
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    /** 두루누비 — 코스 하나. */
    static class FakeDurunubi extends DurunubiApiClient {
        final AtomicInteger pageCalls = new AtomicInteger();
        final AtomicReference<String> failCode = new AtomicReference<>(null);

        FakeDurunubi(LayerCatalogProperties properties) {
            super(null, null, "unused", properties);
        }

        @Override
        public KtoApiClient.Result<List<Course>> fetchCoursePage(int pageNo) {
            pageCalls.incrementAndGet();
            if (failCode.get() != null) {
                return new KtoApiClient.Result.Failed<>(failCode.get(), "가짜 실패");
            }
            if (pageNo > 1) {
                return new KtoApiClient.Result.Empty<>();
            }
            return new KtoApiClient.Result.Ok<>(List.of(new Course("T_ROUTE_1", "서울숲 둘레길", "R1",
                    2.6, 40, 1, "순환", "서울 성동구", "https://fake.durunubi.kr/T_ROUTE_1.gpx")), 1);
        }
    }

    /** GPX 다섯 점 — 서울숲 주변. 첫 점이 카탈로그의 시작점이 돼야 한다. */
    static class FakeGpx extends GpxFetcher {
        static final String GPX = """
                <gpx><trk><trkseg>
                <trkpt lat="37.5445" lon="127.0374"/><trkpt lat="37.5449" lon="127.0379"/>
                <trkpt lat="37.5453" lon="127.0385"/><trkpt lat="37.5455" lon="127.0392"/>
                <trkpt lat="37.5454" lon="127.0400"/>
                </trkseg></trk></gpx>
                """;

        FakeGpx() {
            super(null);
        }

        @Override
        public Optional<String> fetch(String url) {
            return Optional.of(GPX);
        }
    }

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private FakeKto kto;
    @Autowired
    private FakeLocalData localData;
    @Autowired
    private FakeDurunubi durunubi;
    @Autowired
    private LayerCatalogService layers;
    @Autowired
    private PlaceCatalogRepository catalogRows;
    @Autowired
    private KtoBudgetProperties budgetProperties;

    @BeforeEach
    void reset() {
        jdbc.update("delete from kto_call_budget");
        jdbc.update("delete from place_catalog");
        jdbc.update("delete from pet_place_detail");
        jdbc.update("delete from trail_route");
        kto.catalogCalls.set(0);
        kto.nearbyCalls.set(0);
        kto.totalPlaces.set(2);
        localData.pageCalls.set(0);
        localData.failFromPage.set(0);
        localData.failCode.set("999");
        durunubi.pageCalls.set(0);
        durunubi.failCode.set(null);
    }

    // ─────────────────────────── 카탈로그 ───────────────────────────

    @Test
    @DisplayName("KTO 한 벌 뒤에 병원·펫샵·산책로가 이어 붙고, 출처와 좌표(WGS84)가 맞다")
    void layersAreAppendedToTheCatalog() throws Exception {
        String ktoOnlyEtag = mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andReturn().getResponse().getHeader(HttpHeaders.ETAG);

        layers.refreshAll();

        MvcResult res = mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(5))
                .andExpect(jsonPath("$[0].source").value("kto"))
                .andExpect(jsonPath("$[2].source").value("vet"))
                .andExpect(jsonPath("$[2].category").value("vet"))
                .andExpect(jsonPath("$[2].contentId").value("vet:322000001020260003"))
                .andExpect(jsonPath("$[2].contentTypeId").doesNotExist())
                .andExpect(jsonPath("$[3].source").value("shop"))
                .andExpect(jsonPath("$[3].summary").value("동물판매업"))
                .andExpect(jsonPath("$[4].source").value("trail"))
                .andExpect(jsonPath("$[4].contentId").value("trail:T_ROUTE_1"))
                .andExpect(jsonPath("$[4].summary").value("2.6km · 약 40분 · 쉬움 · 순환"))
                .andExpect(jsonPath("$[4].lat").value(37.5445))
                .andExpect(jsonPath("$[4].lng").value(127.0374))
                .andReturn();

        // 인허가 TM 좌표가 WGS84 로 바뀌어 실렸다 — 카카오 정답(37.5079, 127.0333)에서 60m 안.
        JsonNode vet = MAPPER.readTree(res.getResponse().getContentAsString()).get(2);
        assertThat(vet.get("lat").asDouble()).isCloseTo(37.5079, org.assertj.core.data.Offset.offset(0.0006));
        assertThat(vet.get("lng").asDouble()).isCloseTo(127.0333, org.assertj.core.data.Offset.offset(0.0007));

        String combinedEtag = res.getResponse().getHeader(HttpHeaders.ETAG);
        assertThat(combinedEtag).startsWith("W/").isNotEqualTo(ktoOnlyEtag);

        mockMvc.perform(get(CATALOG).header(HttpHeaders.IF_NONE_MATCH, combinedEtag))
                .andExpect(status().isNotModified());
        // 레이어가 붙었으니 옛 ETag 로는 새 본문을 받아야 한다.
        mockMvc.perform(get(CATALOG).header(HttpHeaders.IF_NONE_MATCH, ktoOnlyEtag))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("KTO 한 벌이 없으면 레이어가 있어도 [] 다 — 병원뿐인 한 벌을 앱이 캐시하면 안 된다")
    void noKtoMeansEmptyCatalog() throws Exception {
        layers.refreshAll();
        kto.totalPlaces.set(0);

        mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andExpect(content().string("[]"))
                .andExpect(header().doesNotExist(HttpHeaders.ETAG));
    }

    @Test
    @DisplayName("레이어를 아직 못 받았으면 KTO 한 벌만 그대로 나간다 — 활용신청 전 상태다")
    void ktoAloneWhenLayersAreMissing() throws Exception {
        mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(header().exists(HttpHeaders.ETAG));
    }

    // ─────────────────────────── 주변 조회 ───────────────────────────

    @Test
    @DisplayName("category=vet 는 레이어에서만 거르고 KTO 셀을 부르지 않는다")
    void nearbyVetDoesNotTouchKto() throws Exception {
        layers.refreshAll();

        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.5079").param("lng", "127.0333").param("category", "vet"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].contentId").value("vet:322000001020260003"))
                .andExpect(jsonPath("$[0].distM").isNumber());

        assertThat(kto.nearbyCalls.get()).as("레이어 칩은 KTO 예산을 태우지 않는다").isZero();
    }

    @Test
    @DisplayName("카테고리가 없으면 KTO 셀과 레이어를 합쳐 거리순이다")
    void nearbyWithoutCategoryMergesEverything() throws Exception {
        layers.refreshAll();

        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.5445").param("lng", "127.0374").param("radius", "18000"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(5))
                .andExpect(jsonPath("$[0].contentId").value("100"))
                .andExpect(jsonPath("$[1].contentId").value("trail:T_ROUTE_1"));

        assertThat(kto.nearbyCalls.get()).isEqualTo(1);
    }

    // ─────────────────────────── 산책로 선 ───────────────────────────

    @Test
    @DisplayName("산책로 선은 별도 경로로 받고, 첫 점이 카탈로그의 시작점과 같다")
    void trailRouteIsServedSeparately() throws Exception {
        layers.refreshDurunubi();

        mockMvc.perform(get("/api/places/trails/T_ROUTE_1/route"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, org.hamcrest.Matchers.containsString("max-age=86400")))
                .andExpect(jsonPath("$.courseId").value("T_ROUTE_1"))
                .andExpect(jsonPath("$.name").value("서울숲 둘레길"))
                .andExpect(jsonPath("$.pointCount").value(5))
                .andExpect(jsonPath("$.lengthM").isNumber())
                .andExpect(jsonPath("$.points.length()").value(5))
                .andExpect(jsonPath("$.points[0][0]").value(127.0374))
                .andExpect(jsonPath("$.points[0][1]").value(37.5445));

        mockMvc.perform(get("/api/places/trails/NOPE/route"))
                .andExpect(status().isNotFound());
    }

    // ─────────────────────────── 실패 ───────────────────────────

    @Test
    @DisplayName("중간 페이지가 실패하면 옛 한 벌을 그대로 둔다 — 반쪽보다 옛 것이 낫다")
    void aFailingRefreshKeepsTheOldLayer() throws Exception {
        layers.refreshLocalData();
        PlaceCatalog before = catalogRows.findById(CatalogSource.LOCALDATA.id()).orElseThrow();

        localData.failFromPage.set(1);
        layers.refreshLocalData();

        PlaceCatalog after = catalogRows.findById(CatalogSource.LOCALDATA.id()).orElseThrow();
        assertThat(after.getEtag()).isEqualTo(before.getEtag());
        assertThat(after.getItemCount()).isEqualTo(2);
        assertThat(after.getFailStreak()).isEqualTo(1);
        assertThat(after.getFailedAt()).isNotNull();
    }

    @Test
    @DisplayName("키 미등록(30)을 받으면 그날 인허가 풀을 닫는다 — 활용신청 전에는 더 두드리지 않는다")
    void aKeyErrorClosesTheDayPool() {
        localData.failFromPage.set(1);
        localData.failCode.set("30");

        layers.refreshLocalData();

        Integer used = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'localdata'", Integer.class);
        assertThat(used).isEqualTo(budgetProperties.getLocaldataMaxCallsPerDay());
        assertThat(catalogRows.findById(CatalogSource.LOCALDATA.id()))
                .as("자리표시 행이 생겨 백오프가 걸린다")
                .isPresent();
    }

    @Test
    @DisplayName("두루누비가 실패해도 인허가 한 벌은 저장된다 — 서로 다른 API 다")
    void oneLayerFailingDoesNotBlockTheOther() {
        durunubi.failCode.set("999");

        layers.refreshAll();

        assertThat(catalogRows.findById(CatalogSource.LOCALDATA.id())).isPresent();
        assertThat(catalogRows.findById(CatalogSource.DURUNUBI.id()).map(PlaceCatalog::getItemCount).orElse(0))
                .isZero();
    }
}

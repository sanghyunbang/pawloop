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
import com.heattrip.heat_trip_backend.place.dto.TrailRouteDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;
import com.heattrip.heat_trip_backend.place.layer.DurunubiApiClient;
import com.heattrip.heat_trip_backend.place.layer.GpxFetcher;
import com.heattrip.heat_trip_backend.place.layer.LayerCatalogProperties;
import com.heattrip.heat_trip_backend.place.layer.LayerCatalogService;
import com.heattrip.heat_trip_backend.place.layer.LocalDataApiClient;
import com.heattrip.heat_trip_backend.place.layer.LocalDataBiz;
import com.heattrip.heat_trip_backend.place.layer.LocalTrailAsset;
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

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import com.heattrip.heat_trip_backend.place.layer.LocalTrailAsset;
import com.heattrip.heat_trip_backend.place.layer.PlaygroundAsset;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.mockito.Mockito.when;

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
        /** 주변 조회(셀)에서만 빼는 id — KTO 의 주변 조회는 전국 한 벌보다 좁다(#411 실측). */
        final AtomicReference<String> omitFromNearby = new AtomicReference<>(null);

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
            // 셋째 · 넷째는 겹침 정리(#411)를 보는 테스트만 켠다 — 우리 놀이터 · 동네 길 자산과 같은 자리다.
            if (totalPlaces.get() >= 3) {
                out.add(new PlaceDto("200", "일산호수공원 반려견놀이터", PlaceDto.SOURCE_KTO, "12", "12",
                        37.6640, 126.7660, "경기 고양시", null, "https://tong.visitkorea.or.kr/200.jpg", null));
            }
            if (totalPlaces.get() >= 4) {
                out.add(new PlaceDto("201", "세종호수공원", PlaceDto.SOURCE_KTO, "12", "12",
                        36.5040, 127.2840, "세종특별자치시", null, null, null));
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
            List<PlaceDto> out = places().stream()
                    .filter(p -> !p.contentId().equals(omitFromNearby.get()))
                    .toList();
            return new Result.Ok<>(out, out.size());
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
        /** 업종마다 이만큼의 좌표 없는 행을 더 준다 — 실데이터의 4% 가 그렇다. */
        final AtomicInteger rowsWithoutCoords = new AtomicInteger(0);

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
                List<JsonNode> rows = new ArrayList<>();
                rows.add(MAPPER.readTree(json));
                for (int i = 0; i < rowsWithoutCoords.get(); i++) {
                    rows.add(MAPPER.readTree("{\"MNG_NO\":\"NOCOORD" + i + "\",\"BPLC_NM\":\"좌표 없는 곳\",\"SALS_STTS_CD\":\"01\"}"));
                }
                return new KtoApiClient.Result.Ok<>(rows, rows.size());
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    /** 두루누비 — 코스 하나. */
    static class FakeDurunubi extends DurunubiApiClient {
        final AtomicInteger pageCalls = new AtomicInteger();
        final AtomicReference<String> failCode = new AtomicReference<>(null);
        /** GPX 주소가 죽은 코스를 하나 더 준다. */
        final AtomicBoolean extraCourseWithBrokenGpx = new AtomicBoolean(false);

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
            List<Course> courses = new ArrayList<>();
            courses.add(new Course("T_ROUTE_1", "서울숲 둘레길", "R1",
                    2.6, 40, 1, "순환", "서울 성동구", "https://fake.durunubi.kr/T_ROUTE_1.gpx"));
            if (extraCourseWithBrokenGpx.get()) {
                courses.add(new Course("T_ROUTE_BROKEN", "GPX 가 죽은 길", "R2",
                        1.0, 20, 1, "순환", "서울 성동구", "https://fake.durunubi.kr/BROKEN.gpx"));
            }
            return new KtoApiClient.Result.Ok<>(courses, courses.size());
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
            return url.contains("BROKEN") ? Optional.empty() : Optional.of(GPX);
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

    /**
     * 동네 길 자산을 <b>비운다</b> — 이슈 #346.
     *
     * <p>이 클래스가 재는 것은 <b>API 로 오는 레이어</b>(인허가·두루누비)의 적재와 이어
     * 붙이기다. 저장소에 커밋된 실자산 1,302개가 함께 담기면 여기 숫자가 전부 바뀌고,
     * 자산을 새로 만드는 날마다 이 테스트가 깨진다 — 그건 이 테스트가 지키는 것이 아니다.
     * 자산 자체는 {@code LocalTrailAssetTest} 와
     * {@code LocalTrailAssetRouteTest} 가 실파일로 따로 잰다.
     */
    @MockitoBean
    private LocalTrailAsset localTrails;

    /** 놀이터 자산도 같은 이유로 비운다 — {@code PlaygroundAssetTest} 가 따로 잰다. */
    @MockitoBean
    private PlaygroundAsset playgrounds;

    @BeforeEach
    void reset() {
        when(localTrails.load()).thenReturn(List.of());
        when(playgrounds.load()).thenReturn(List.of());
        jdbc.update("delete from kto_call_budget");
        jdbc.update("delete from place_catalog");
        jdbc.update("delete from pet_place_detail");
        jdbc.update("delete from trail_route");
        kto.catalogCalls.set(0);
        kto.nearbyCalls.set(0);
        kto.totalPlaces.set(2);
        kto.omitFromNearby.set(null);
        jdbc.update("delete from place_cell");
        localData.pageCalls.set(0);
        localData.failFromPage.set(0);
        localData.failCode.set("999");
        durunubi.pageCalls.set(0);
        durunubi.failCode.set(null);
        localData.rowsWithoutCoords.set(0);
        durunubi.extraCourseWithBrokenGpx.set(false);
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
    @DisplayName("category=trail 은 반경을 안 본다 — 부산에서 물어도 서울숲 둘레길이 거리와 함께 온다 (2026-09-06 결정)")
    void nearbyTrailIgnoresTheRadius() throws Exception {
        layers.refreshAll();

        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "35.1796").param("lng", "129.0756").param("category", "trail"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].contentId").value("trail:T_ROUTE_1"))
                .andExpect(jsonPath("$[0].distM").value(org.hamcrest.Matchers.greaterThan(300000.0)));

        // 반경을 푸는 것은 산책로뿐이다 — 병원은 부산 8km 안에 없으니 빈 목록이다.
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "35.1796").param("lng", "129.0756").param("category", "vet"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
        assertThat(kto.nearbyCalls.get()).isZero();
    }

    @Test
    @DisplayName("동네 길 자산이 카탈로그 응답까지 간다 — 출처를 손으로 세면 여기가 빈다")
    void localTrailsReachTheCatalog() throws Exception {
        // 자산이 주는 모양 그대로 — 두루누비와 안 겹치는 trail:lt… 다.
        // 좌표는 KTO "서울숲"(37.5445, 127.0374)에서 330m 뗀다 — 같은 자리면 이름이 그쪽을 포함해
        // 겹침 정리(#411)가 이 길을 빼는 것이 맞고, 이 테스트가 보려는 것은 그것이 아니다.
        when(localTrails.load()).thenReturn(List.of(
                new PlaceDto("trail:ltaaaa1", "서울숲길", PlaceDto.SOURCE_TRAIL, PlaceDto.SOURCE_TRAIL,
                        null, 37.5475, 127.0374, "서울특별시 성동구", null, null, null, "4.2km · 약 1시간"),
                new PlaceDto("trail:ltaaaa2", "한강수변길", PlaceDto.SOURCE_TRAIL, PlaceDto.SOURCE_TRAIL,
                        null, 37.5450, 127.0400, "서울특별시 성동구", null, null, null, "6.6km · 약 2시간")));

        layers.refreshAll();

        // #346 전에는 카탈로그를 잇는 곳 둘이 출처 이름을 손으로 적어 두고 있었다
        // (PlaceCatalogService · LayerPlaceIndex). 그래서 place_catalog 에는 담겼는데
        // 이 응답에는 한 곳도 안 나왔다. 열거형을 도는 지금은 저절로 따라온다.
        mockMvc.perform(get("/api/places/catalog"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == 'trail:ltaaaa1')].title").value("서울숲길"))
                .andExpect(jsonPath("$[?(@.contentId == 'trail:ltaaaa2')].title").value("한강수변길"));

        // 주변 조회도 같은 한 벌을 본다 — 여기가 비면 산책로 칩이 코리아둘레길로 돌아간다.
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.5445").param("lng", "127.0374").param("category", "trail"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == 'trail:ltaaaa1')].title").value("서울숲길"));
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

    @Test
    @DisplayName("선이 있는 코스도 waypoints 칸을 비워서 내보낸다 — 앱이 칸 없는 본문을 안 만나게")
    void aLineRouteStillCarriesTheWaypointsField() throws Exception {
        layers.refreshDurunubi();

        mockMvc.perform(get("/api/places/trails/T_ROUTE_1/route"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.waypoints").isArray())
                .andExpect(jsonPath("$.waypoints.length()").value(0));
    }

    @Test
    @DisplayName("동네 길을 누르면 거쳐 가는 곳으로 답한다 — 예전에는 404 라 아무 일도 안 났다 (#619)")
    void aLocalTrailAnswersWithItsStops() throws Exception {
        // 목록에 실제로 나가는 항목에서 코스 번호를 뽑는다. 여기서 번호를 손으로 적으면
        // contentId 규칙이 바뀌어도 이 검사는 계속 초록이다 — 그게 이 버그의 모양이었다.
        // 여기서 재는 것은 **배선**이다 — 표에 없을 때 자산까지 물어보는가, 그리고 그 답이
        // 계약대로 나가는가. 자산 자체(1,302개를 실제로 자르는 일)는 위 javadoc 의 이유로
        // 여기서 목이고, LocalTrailAssetRouteTest 가 실파일로 잰다.
        when(localTrails.route("lt0f1e2d3c"))
                .thenReturn(Optional.of(TrailRouteDto.ofStops(
                        "lt0f1e2d3c", "도봉 역사문화 길", 4200,
                        List.of("보신각", "보성사 터", "탑골공원"))));

        mockMvc.perform(get("/api/places/trails/lt0f1e2d3c/route"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.courseId").value("lt0f1e2d3c"))
                .andExpect(jsonPath("$.name").value("도봉 역사문화 길"))
                .andExpect(jsonPath("$.lengthM").value(4200))
                .andExpect(jsonPath("$.pointCount").value(0))
                .andExpect(jsonPath("$.points").isArray())
                .andExpect(jsonPath("$.points.length()").value(0))
                .andExpect(jsonPath("$.waypoints.length()").value(3))
                .andExpect(jsonPath("$.waypoints[0]").value("보신각"))
                .andExpect(jsonPath("$.waypoints[2]").value("탑골공원"));
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

    // ─────────────────────────── 전체 수 ───────────────────────────

    @Test
    @DisplayName("좌표 없는 행은 전체 수에서도 뺀다 — 다 받았는데 '잘렸다'가 되면 안 된다")
    void rowsWithoutCoordinatesDoNotCountAsTruncation() {
        localData.rowsWithoutCoords.set(3);

        layers.refreshLocalData();

        PlaceCatalog row = catalogRows.findById(CatalogSource.LOCALDATA.id()).orElseThrow();
        assertThat(row.getItemCount()).as("병원 하나 · 판매업 하나만 담긴다").isEqualTo(2);
        assertThat(row.getTotalCount())
                .as("실측(#291)에서 API 전체 8,110 중 좌표 없는 354 때문에 경고가 헛울렸다")
                .isEqualTo(row.getItemCount());
    }

    @Test
    @DisplayName("GPX 를 못 받은 코스는 전체 수에서도 뺀다 — 못 받음은 따로 세고 '잘렸다'는 아니다")
    void coursesWithoutGpxDoNotCountAsTruncation() {
        durunubi.extraCourseWithBrokenGpx.set(true);

        layers.refreshDurunubi();

        PlaceCatalog row = catalogRows.findById(CatalogSource.DURUNUBI.id()).orElseThrow();
        assertThat(row.getItemCount()).isEqualTo(1);
        assertThat(row.getTotalCount()).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from trail_route", Integer.class)).isEqualTo(1);
    }
    // ─────────────── 갱신 배치 — 자산 두 벌 (#346) ───────────────
    //
    // 동네 길과 놀이터는 **외부를 안 부른다.** 저장소에 커밋한 파일을 읽어 한 벌로 담는
    // 것이 전부다(원본 갱신주기가 "연간" 이고, 놀이터는 전국 표준데이터가 아예 없다).
    //
    // 그래서 여기서 재는 것은 "받아 오는가" 가 아니라 **담기는가**다.
    //   · 자산에 있는 개수가 그대로 한 벌이 되는가
    //   · 두 번 돌려도 행이 안 늘어나는가
    //   · 자산이 비었을 때 **지난 한 벌을 안 지우는가** — 빈 한 벌로 덮으면 그 순간
    //     지도에서 동네 길이 통째로 사라진다
    //   · 예산도 외부 호출도 안 쓰는가

    @Test
    @DisplayName("동네 길 갱신이 자산 개수 그대로 한 벌을 담는다 — 외부는 한 번도 안 부른다")
    void localTrailRefreshStoresTheWholeAsset() {
        List<PlaceDto> asset = new LocalTrailAsset(MAPPER).load();
        when(localTrails.load()).thenReturn(asset);

        layers.refreshLocalTrails();

        PlaceCatalog stored = catalogRows.findById(CatalogSource.LOCALTRAIL.id()).orElseThrow();
        assertThat(stored.getItemCount())
                .as("자산 %d개가 그대로 담겨야 한다", asset.size())
                .isEqualTo(asset.size());
        assertThat(stored.getTotalCount()).isEqualTo(asset.size());
        assertThat(kto.catalogCalls.get() + kto.nearbyCalls.get()
                + localData.pageCalls.get() + durunubi.pageCalls.get())
                .as("자산에서 읽는 갱신이 외부를 부르면 예산이 새는 것이다")
                .isZero();
    }

    @Test
    @DisplayName("놀이터 갱신도 같다 — 자산 개수 그대로")
    void playgroundRefreshStoresTheWholeAsset() {
        List<PlaceDto> asset = new PlaygroundAsset(MAPPER).load();
        when(playgrounds.load()).thenReturn(asset);

        layers.refreshPlaygrounds();

        PlaceCatalog stored = catalogRows.findById(CatalogSource.PLAYGROUND.id()).orElseThrow();
        assertThat(stored.getItemCount()).isEqualTo(asset.size());
    }

    @Test
    @DisplayName("두 번 돌려도 행이 하나다 — 배포마다 도는 배치라 쌓이면 안 된다")
    void refreshingTwiceKeepsOneRow() {
        List<PlaceDto> asset = new LocalTrailAsset(MAPPER).load();
        when(localTrails.load()).thenReturn(asset);

        layers.refreshLocalTrails();
        layers.refreshLocalTrails();

        assertThat(jdbc.queryForObject(
                "select count(*) from place_catalog where source = 'localtrail'", Integer.class))
                .isEqualTo(1);
        assertThat(catalogRows.findById(CatalogSource.LOCALTRAIL.id()).orElseThrow().getItemCount())
                .isEqualTo(asset.size());
    }

    @Test
    @DisplayName("자산이 비면 지난 한 벌을 그대로 둔다 — 빈 한 벌로 덮으면 동네 길이 사라진다")
    void anEmptyAssetDoesNotWipeTheStoredBatch() {
        List<PlaceDto> asset = new LocalTrailAsset(MAPPER).load();
        when(localTrails.load()).thenReturn(asset);
        layers.refreshLocalTrails();

        // 파일이 깨졌거나 못 읽은 상황.
        when(localTrails.load()).thenReturn(List.of());
        layers.refreshLocalTrails();

        assertThat(catalogRows.findById(CatalogSource.LOCALTRAIL.id()).orElseThrow().getItemCount())
                .as("빈 한 벌로 덮으면 그 순간부터 지도에서 동네 길이 통째로 사라진다")
                .isEqualTo(asset.size());
    }

    @Test
    @DisplayName("담은 한 벌이 카탈로그 응답의 동네 길 개수와 같다 — 담기만 하고 안 나가면 소용없다")
    void theStoredBatchReachesTheResponse() throws Exception {
        List<PlaceDto> asset = new LocalTrailAsset(MAPPER).load();
        when(localTrails.load()).thenReturn(asset);
        layers.refreshLocalTrails();
        // KTO 한 벌이 없으면 응답이 [] 다(위 테스트가 그것을 잰다). 한 벌을 먼저 만든다.
        mockMvc.perform(get(CATALOG)).andExpect(status().isOk());

        JsonNode body = MAPPER.readTree(mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));

        long served = 0;
        for (JsonNode place : body) {
            if (place.path("contentId").asText("").startsWith("trail:lt")) {
                served++;
            }
        }
        assertThat(served).isEqualTo(asset.size());
    }

    // ─────────────────────────── 겹치는 자리 (#411) ───────────────────────────

    @Test
    @DisplayName("우리 자산이 관광공사 항목과 같은 자리면 빠지고, 놀이터는 관광공사 항목에 옮겨 달린다 — 카탈로그 · 놀이터 칩 · 전체 · 여행지 칩 (#411)")
    void overlappingAssetsYieldToKto() throws Exception {
        kto.totalPlaces.set(4);
        when(playgrounds.load()).thenReturn(List.of(
                // 관광공사 "일산호수공원 반려견놀이터"(200) 에서 33m — 이름은 한 칸 다르다.
                new PlaceDto("playground:ovl", "일산호수공원 반려견 놀이터", PlaceDto.SOURCE_PLAYGROUND,
                        PlaceDto.SOURCE_PLAYGROUND, null, 37.6643, 126.7660, "경기 고양시", "031-000-0000", null, null, null),
                // 1.3km 떨어진 다른 놀이터 — 그대로 남아야 한다.
                new PlaceDto("playground:keep", "정발산 반려견 놀이터", PlaceDto.SOURCE_PLAYGROUND,
                        PlaceDto.SOURCE_PLAYGROUND, null, 37.6700, 126.7800, "경기 고양시", null, null, null, null)));
        when(localTrails.load()).thenReturn(List.of(
                // 관광공사 "세종호수공원"(201) 에서 22m — 이름이 그쪽을 포함한다. 빠지되 옮기지 않는다.
                new PlaceDto("trail:ltovl", "세종호수공원 산책로", PlaceDto.SOURCE_TRAIL, PlaceDto.SOURCE_TRAIL,
                        null, 36.5042, 127.2840, "세종특별자치시", null, null, null, "3.0km · 약 40분")));

        layers.refreshAll();

        mockMvc.perform(get(CATALOG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == 'playground:ovl')]").isEmpty())
                .andExpect(jsonPath("$[?(@.contentId == 'trail:ltovl')]").isEmpty())
                .andExpect(jsonPath("$[?(@.contentId == 'playground:keep')].title").value("정발산 반려견 놀이터"))
                .andExpect(jsonPath("$[?(@.contentId == '200')].source").value("kto"))
                .andExpect(jsonPath("$[?(@.contentId == '200')].category").value("playground"))
                .andExpect(jsonPath("$[?(@.contentId == '200')].contentTypeId").isEmpty())
                .andExpect(jsonPath("$[?(@.contentId == '200')].tel").value("031-000-0000"))
                .andExpect(jsonPath("$[?(@.contentId == '200')].image").value("https://tong.visitkorea.or.kr/200.jpg"))
                .andExpect(jsonPath("$[?(@.contentId == '201')].category").value("12"))
                .andExpect(jsonPath("$[?(@.contentId == '201')].contentTypeId").value("12"))
                // KTO 넷 + 병원 · 펫샵 · 두루누비 + 남은 놀이터 하나 = 8. 겹친 둘이 빠졌다.
                .andExpect(jsonPath("$.length()").value(8));

        // 놀이터 칩 — KTO 셀을 안 부르는 길인데도 옮겨 단 관광공사 항목이 온다.
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.6640").param("lng", "126.7660").param("category", "playground"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].contentId").value("200"))
                .andExpect(jsonPath("$[0].source").value("kto"))
                .andExpect(jsonPath("$[0].category").value("playground"))
                .andExpect(jsonPath("$[1].contentId").value("playground:keep"));
        assertThat(kto.nearbyCalls.get()).as("놀이터 칩은 KTO 예산을 태우지 않는다").isZero();

        // 전체 — 셀에 있으면 사본으로 바뀐 채 한 번만, 놀이터로.
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.6640").param("lng", "126.7660"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == '200')]", org.hamcrest.Matchers.hasSize(1)))
                .andExpect(jsonPath("$[?(@.contentId == '200')].category").value("playground"))
                .andExpect(jsonPath("$[?(@.contentId == 'playground:ovl')]").isEmpty());

        // 전체 — 셀에 없어도 한 번은 온다. KTO 의 주변 조회는 전국 한 벌보다 좁아서 일산 셀 19곳에
        // "일산호수공원 반려견놀이터" 가 없었다(2026-09-14 실측) — 그러면 우리 놀이터를 뺀 자리가 비어
        // 사용자는 그 놀이터를 전체 목록에서 잃는다.
        jdbc.update("delete from place_cell");
        kto.omitFromNearby.set("200");
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.6640").param("lng", "126.7660"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == '200')]", org.hamcrest.Matchers.hasSize(1)))
                .andExpect(jsonPath("$[?(@.contentId == '200')].category").value("playground"))
                .andExpect(jsonPath("$[?(@.contentId == '200')].source").value("kto"));

        // 여행지 칩 — 놀이터로 옮겨 갔으니 여기엔 없다.
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.6640").param("lng", "126.7660").param("category", "12"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.contentId == '200')]").isEmpty());
    }

    @Test
    @DisplayName("겹침 정리가 들어가면 같은 행이라도 ETag 가 바뀐다 — 옛 본문을 캐시한 앱이 304 만 받으면 안 된다")
    void catalogEtagChangesWithTheServedFormat() throws Exception {
        layers.refreshAll();

        String etag = mockMvc.perform(get(CATALOG)).andReturn().getResponse().getHeader(HttpHeaders.ETAG);
        List<String> rowEtags = new ArrayList<>();
        for (CatalogSource source : CatalogSource.values()) {
            catalogRows.etagOf(source.id()).ifPresent(rowEtags::add);
        }
        // 행의 ETag 만 섞은 옛 값(#291 의 공식: sha256 을 32자로 자른 것)과 다르다.
        byte[] digest = java.security.MessageDigest.getInstance("SHA-256")
                .digest(String.join("|", rowEtags).getBytes(StandardCharsets.UTF_8));
        String legacy = java.util.HexFormat.of().formatHex(digest).substring(0, 32);
        assertThat(etag).isNotEqualTo("W/\"" + legacy + "\"");
        mockMvc.perform(get(CATALOG).header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isNotModified());
    }
}

package com.heattrip.heat_trip_backend.place;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.heattrip.heat_trip_backend.place.dto.PetInfoDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.repository.PlaceCatalogRepository;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;
import com.heattrip.heat_trip_backend.place.service.PlaceCatalogService;
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

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 전국 카탈로그 경로 — 이슈 #273 (#235 A4).
 *
 * <h2>여기서 재는 것</h2>
 * <p>이 경로의 존재 이유는 <b>요청에 좌표가 없다</b>는 것이고, 그것이 성립하려면 나머지가
 * 전부 맞아야 한다 — 한 벌을 페이지로 다 받는가, 중간에 실패하면 반쪽을 저장하지 않는가,
 * ETag 가 내용 해시라 안 바뀐 날 304 가 나오는가, 빈 답에 ETag 를 안 붙이는가.
 *
 * <p>KTO 는 {@link PlaceProxyIntegrationTest} 와 같은 이유로 <b>가짜로 갈아끼운다.</b>
 * 진짜를 부르면 CI 가 도는 날마다 하루 예산이 탄다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ContextConfiguration(classes = PlaceCatalogIntegrationTest.StubbedKto.class)
class PlaceCatalogIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String PATH = "/api/places/catalog";

    @TestConfiguration
    static class StubbedKto {
        @Bean
        @Primary
        FakeCatalogKto fakeCatalogKto() {
            return new FakeCatalogKto();
        }
    }

    /**
     * 페이지 단위로 답하는 가짜 KTO.
     *
     * <p>{@link KtoApiClient} 를 상속한다 — 인터페이스를 새로 파면 진짜 구현이 그것을 따르는지
     * 아무도 안 보게 되고, 그러면 이 테스트가 실제 클라이언트와 갈라진다.
     */
    static class FakeCatalogKto extends KtoApiClient {

        /** 한 페이지에 담는 수. 진짜의 {@code numOfRows} 자리다. */
        static final int PAGE_SIZE = 2;

        final AtomicInteger pageCalls = new AtomicInteger();

        /** 전국에 있다고 할 장소 수. */
        final AtomicInteger totalPlaces = new AtomicInteger(3);

        /** 이 페이지부터 실패한다. 0 이면 실패가 없다. */
        final AtomicInteger failFromPage = new AtomicInteger(0);

        final AtomicReference<String> failCode = new AtomicReference<>("999");

        FakeCatalogKto() {
            super(null, null, null, "unused", PAGE_SIZE);
        }

        @Override
        public Result<List<PlaceDto>> fetchCatalogPage(int pageNo) {
            pageCalls.incrementAndGet();
            if (failFromPage.get() > 0 && pageNo >= failFromPage.get()) {
                return new Result.Failed<>(failCode.get(), "가짜 실패");
            }
            int total = totalPlaces.get();
            if (total == 0) {
                return new Result.Empty<>();
            }
            List<PlaceDto> page = new ArrayList<>();
            for (int i = (pageNo - 1) * PAGE_SIZE; i < Math.min(pageNo * PAGE_SIZE, total); i++) {
                page.add(new PlaceDto(String.valueOf(100 + i), "장소" + i, PlaceDto.SOURCE_KTO,
                        "12", "12", 37.5 + i * 0.01, 127.0 + i * 0.01,
                        "주소" + i, null, null, null));
            }
            return new Result.Ok<>(page, total);
        }

        @Override
        public Result<String> fetchOverview(String contentId) {
            return new Result.Ok<>("개요입니다", 1);
        }

        @Override
        public Result<PetInfoDto> fetchPetInfo(String contentId) {
            return new Result.Ok<>(new PetInfoDto("소형견", "목줄 필수", null), 1);
        }
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private FakeCatalogKto kto;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PlaceCatalogService service;

    @Autowired
    private PlaceCatalogRepository catalogRows;

    @Autowired
    private Clock clock;

    @BeforeEach
    void reset() {
        jdbc.update("delete from kto_call_budget");
        jdbc.update("delete from place_catalog");
        jdbc.update("delete from pet_place_detail");
        kto.pageCalls.set(0);
        kto.totalPlaces.set(3);
        kto.failFromPage.set(0);
        kto.failCode.set("999");
    }

    // ─────────────────────────── 요청에 좌표가 없다 ───────────────────────────

    @Test
    @DisplayName("좌표 없이 부를 수 있고 인증도 없다 — 이 경로의 존재 이유가 그것이다")
    void theCatalogTakesNoCoordinatesAndNoAuth() throws Exception {
        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].source").value("kto"));
    }

    @Test
    @DisplayName("거리를 안 싣는다 — 서버가 그 값을 계산할 좌표를 갖고 있지 않다")
    void theCatalogCarriesNoDistance() throws Exception {
        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].distM").doesNotExist());
    }

    // ─────────────────────────── 페이지 ───────────────────────────

    @Test
    @DisplayName("totalCount 만큼 페이지를 다 받는다 — 한 페이지만 받으면 지도의 대부분이 사라진다")
    void everyPageIsFetched() throws Exception {
        kto.totalPlaces.set(5);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(5));

        assertThat(kto.pageCalls.get())
                .as("한 페이지가 2개니 5개를 받으려면 3콜이다")
                .isEqualTo(3);
    }

    @Test
    @DisplayName("두 번째 요청은 KTO 를 안 부른다 — 캐시가 없으면 요청마다 열 콜이 나간다")
    void theSecondRequestCostsNothing() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());
        int after = kto.pageCalls.get();

        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        assertThat(kto.pageCalls.get()).isEqualTo(after);
    }

    @Test
    @DisplayName("중간 페이지가 실패하면 반쪽을 저장하지 않는다 — 지도에서 장소가 조용히 사라진다")
    void aPartialFetchIsNotStored() throws Exception {
        kto.totalPlaces.set(5);
        kto.failFromPage.set(2);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(content().string("[]"));

        Integer rows = jdbc.queryForObject(
                "select count(*) from place_catalog where item_count > 0", Integer.class);
        assertThat(rows)
                .as("""
                        반쪽을 저장하면 그 상태가 캐시 수명만큼 굳는다. 옛 한 벌이 반쪽보다 낫고, \
                        한 벌이 아예 없으면 빈 배열이 낫다 — 둘 다 '조용히 줄어든 지도' 보다 낫다.""")
                .isZero();
    }

    @Test
    @DisplayName("실패해도 갖고 있던 한 벌은 계속 준다")
    void aFailureKeepsServingWhatWeHave() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        jdbc.update("update place_catalog set fetched_at = fetched_at - interval 10 day");
        kto.failFromPage.set(1);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));
    }

    @Test
    @DisplayName("전국이 0곳으로 오면 저장하지 않는다 — 셀과 반대다. 전국이 빈 것은 정상이 아니다")
    void anEmptyCountryIsNotStored() throws Exception {
        kto.totalPlaces.set(0);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(content().string("[]"));

        // **여기서 재는 것은 행의 유무가 아니라 「굳었는가」 다.** 빈 한 벌을 신선한 것으로
        // 저장하면 그 순간부터 캐시 수명(기본 24시간) 동안 갱신을 시도조차 안 한다 —
        // KTO 가 그 사이 회복해도 지도가 계속 비어 있다.
        //
        // 행만 세면 이 검사가 아무것도 안 잰다. 서빙 쪽이 item_count = 0 을 이미 거르므로,
        // 저장하든 안 하든 응답은 똑같이 [] 다(실측 — 가드를 지워도 초록불이었다).
        kto.totalPlaces.set(3);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));
    }

    // ─────────────────────────── ETag ───────────────────────────

    @Test
    @DisplayName("ETag 를 주고, 같은 값을 되보내면 304 다 — 본문이 안 나간다")
    void anUnchangedCatalogAnswers304() throws Exception {
        String etag = mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(header().exists(HttpHeaders.ETAG))
                .andReturn().getResponse().getHeader(HttpHeaders.ETAG);

        mockMvc.perform(get(PATH).header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isNotModified())
                .andExpect(content().string(""));
    }

    @Test
    @DisplayName("갱신해도 내용이 같으면 ETag 가 안 바뀐다 — 시각으로 만들면 매번 2.83MB 를 다시 받는다")
    void theEtagFollowsContentNotTime() throws Exception {
        String first = mockMvc.perform(get(PATH)).andReturn()
                .getResponse().getHeader(HttpHeaders.ETAG);

        // 낡게 만들어 갱신을 강제한다. KTO 는 같은 것을 다시 준다.
        jdbc.update("update place_catalog set fetched_at = fetched_at - interval 10 day");

        String second = mockMvc.perform(get(PATH)).andReturn()
                .getResponse().getHeader(HttpHeaders.ETAG);

        assertThat(second)
                .as("""
                        fetched_at 을 ETag 로 쓰면 KTO 데이터가 그대로여도 갱신마다 값이 바뀌어 \
                        앱이 한 벌을 통째로 다시 받는다. 그러면 304 를 둔 이유가 사라진다.""")
                .isEqualTo(first);
    }

    @Test
    @DisplayName("W/ 접두사와 콤마 목록도 받는다 — 프록시가 그렇게 보낸다")
    void weakValidatorsAndListsAreAccepted() throws Exception {
        String etag = mockMvc.perform(get(PATH)).andReturn()
                .getResponse().getHeader(HttpHeaders.ETAG);

        mockMvc.perform(get(PATH).header(HttpHeaders.IF_NONE_MATCH, "W/" + etag))
                .andExpect(status().isNotModified());
        mockMvc.perform(get(PATH).header(HttpHeaders.IF_NONE_MATCH, "\"other\", " + etag))
                .andExpect(status().isNotModified());
        mockMvc.perform(get(PATH).header(HttpHeaders.IF_NONE_MATCH, "\"other\""))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("한 벌이 없어 빈 배열을 줄 때는 ETag 를 안 붙인다 — 붙이면 빈 지도가 굳는다")
    void anEmptyAnswerCarriesNoEtag() throws Exception {
        kto.failFromPage.set(1);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(content().string("[]"))
                .andExpect(header().doesNotExist(HttpHeaders.ETAG));
    }

    // ─────────────────────────── 예산 · 허용목록 ───────────────────────────

    @Test
    @DisplayName("예산이 없으면 KTO 를 안 부르고 갖고 있던 한 벌을 준다")
    void anExhaustedBudgetStillServesWhatWeHave() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        jdbc.update("update place_catalog set fetched_at = fetched_at - interval 10 day");
        jdbc.update("update kto_call_budget set used = 999999 where pool = 'catalog'");
        int before = kto.pageCalls.get();

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));

        assertThat(kto.pageCalls.get()).isEqualTo(before);
    }

    @Test
    @DisplayName("카탈로그는 nearby 와 다른 예산 풀을 쓴다 — 한쪽이 태워도 다른 쪽이 살아야 한다")
    void theCatalogHasItsOwnPool() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        Integer catalogUsed = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'catalog'", Integer.class);
        Integer nearbyRows = jdbc.queryForObject(
                "select count(*) from kto_call_budget where pool = 'nearby'", Integer.class);

        assertThat(catalogUsed).isNotNull().isPositive();
        assertThat(nearbyRows)
                .as("두 경로는 서로 다른 빌드가 쓴다. 한 풀이면 한쪽이 다른 쪽을 죽인다")
                .isZero();
    }

    @Test
    @DisplayName("카탈로그로 받은 장소는 상세를 열 수 있다 — 등재를 빠뜨리면 목록에만 있고 못 누른다")
    void catalogPlacesAreOpenableForDetail() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        mockMvc.perform(get("/api/places/100"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.contentId").value("100"));
    }

    @Test
    @DisplayName("카탈로그에 없는 id 는 여전히 404 다 — 허용목록이 넓어진 것이지 사라진 게 아니다")
    void unknownIdsAreStill404() throws Exception {
        mockMvc.perform(get(PATH)).andExpect(status().isOk());

        mockMvc.perform(get("/api/places/999999999"))
                .andExpect(status().isNotFound());
    }

    // ─────────────────────────── 예열 (#279) ───────────────────────────
    //
    // 새벽 cron 이 부르는 warmUp() 이 사용자 요청과 같은 길을 지나는지 잰다. 시각(cron)은
    // PlaceCatalogWarmupSchedulerTest·PlaceCatalogWarmupWiringTest 가 재고, 여기서는
    // "무엇을 하는가" 만 본다.

    @Test
    @DisplayName("예열은 한 벌이 없으면 받아서 저장한다 — 그 뒤 첫 사용자 요청은 KTO 를 안 부른다")
    void warmUp_fetchesAndTheFirstUserRequestCostsNothing() throws Exception {
        service.warmUp();

        int afterWarmUp = kto.pageCalls.get();
        assertThat(afterWarmUp).as("3곳을 2곳씩 두 페이지로 받는다").isEqualTo(2);
        Integer stored = jdbc.queryForObject(
                "select item_count from place_catalog where id = 1", Integer.class);
        assertThat(stored).isEqualTo(3);

        mockMvc.perform(get(PATH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));

        assertThat(kto.pageCalls.get())
                .as("이것이 #279 의 목적이다 — 첫 사람이 16초를 기다리지 않는다")
                .isEqualTo(afterWarmUp);
    }

    @Test
    @DisplayName("예열은 낡지 않은 한 벌을 다시 받지 않는다 — 서버가 여러 대여도 예산이 안 샌다")
    void warmUp_doesNothingWhenTheCatalogIsFresh() {
        service.warmUp();
        int after = kto.pageCalls.get();

        service.warmUp();

        assertThat(kto.pageCalls.get()).isEqualTo(after);
    }

    @Test
    @DisplayName("예열은 낡은 한 벌을 갈아 끼운다 — 사용자 요청과 같은 기준으로")
    void warmUp_refreshesAStaleCatalog() {
        service.warmUp();
        jdbc.update("update place_catalog set fetched_at = fetched_at - interval 10 day");
        int before = kto.pageCalls.get();

        service.warmUp();

        assertThat(kto.pageCalls.get()).isGreaterThan(before);
        // fetched_at 은 서비스 존(Asia/Seoul)의 벽시계다 — PlaceCatalog 의 필드 설명 그대로.
        // 그래서 SQL 의 utc_timestamp() 와 견주면 9시간이 어긋난다(첫 판이 그렇게 빨갰다).
        // 서비스가 쓰는 바로 그 Clock 으로 "방금" 을 만든다.
        LocalDateTime fetchedAt = catalogRows.findById(1).orElseThrow().getFetchedAt();
        assertThat(Duration.between(fetchedAt, LocalDateTime.now(clock)).abs())
                .as("fetched_at 이 방금으로 돌아와야 한다 — 열흘 전 그대로면 예열이 저장을 안 한 것이다")
                .isLessThan(Duration.ofMinutes(1));
    }

    @Test
    @DisplayName("예열은 카탈로그 예산 풀을 쓴다 — 사용자 요청과 같은 상한이다")
    void warmUp_spendsTheCatalogPool() {
        service.warmUp();

        Integer catalogUsed = jdbc.queryForObject(
                "select used from kto_call_budget where pool = 'catalog'", Integer.class);
        Integer otherPools = jdbc.queryForObject(
                "select count(*) from kto_call_budget where pool <> 'catalog'", Integer.class);

        assertThat(catalogUsed).isNotNull().isPositive();
        assertThat(otherPools).as("예열이 다른 풀을 쓰면 상한이 둘이 된다").isZero();
    }

    @Test
    @DisplayName("예열은 KTO 가 죽어도 던지지 않는다 — 잡이 예외로 죽으면 다음 날 아무도 모른다")
    void warmUp_swallowsAnUpstreamFailure() {
        kto.failFromPage.set(1);

        assertThatCode(service::warmUp).doesNotThrowAnyException();

        Integer rows = jdbc.queryForObject(
                "select count(*) from place_catalog where item_count > 0", Integer.class);
        assertThat(rows).as("실패는 저장하지 않는다 — 빈 한 벌이 굳으면 지도가 빈다").isZero();
    }
}

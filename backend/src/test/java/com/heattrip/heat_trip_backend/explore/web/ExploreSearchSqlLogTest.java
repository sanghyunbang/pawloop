package com.heattrip.heat_trip_backend.explore.web;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import javax.sql.DataSource;
import java.time.LocalDateTime;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultHandlers.print;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /api/explore/places/search} 의 조건 조합별 동작.
 *
 * <h2>왜 실제 MySQL 위에서 도는가</h2>
 * <p>키워드 검색은 {@code MATCH(p.search_text) AGAINST (:keyword IN BOOLEAN MODE)} 라는
 * MySQL FULLTEXT 전용 문법을 쓴다. H2 에는 없어서 Case 5·6 이 500 으로 죽었고, 이슈 #22 가
 * {@code @Tag("mysql")} 로 기본 실행에서 빼 두었다. 그 결과 검색의 핵심 경로가 CI 에서
 * 한 번도 검증되지 않았다. 이슈 #26 이 Testcontainers 로 그 격리를 걷어낸다.</p>
 *
 * <h2>왜 status 200 만으로는 부족한가</h2>
 * <p>FULLTEXT 는 조건이 어긋나면 <b>예외 없이 0건</b>을 돌려준다. 예컨대 컨테이너가
 * {@code innodb_ft_min_token_size} 기본값 3 으로 뜨면 2글자인 "카페"는 색인도 검색도 되지 않아
 * 200 + 빈 목록이 된다. 그래서 여기서는 200 만 보지 않고 <b>어떤 행이 잡혔는지</b>까지 본다.
 * 컨테이너 플래그 자체는 {@code MySqlComposeParityTest} 가 compose 와 대조한다.</p>
 */
@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = {
        "spring.jpa.show-sql=true",
        "spring.jpa.properties.hibernate.format_sql=true",
        "logging.level.org.hibernate.SQL=DEBUG",
        "logging.level.org.hibernate.orm.jdbc.bind=TRACE",
        "logging.level.org.springframework.transaction=TRACE"
})
class ExploreSearchSqlLogTest extends AbstractMySqlIntegrationTest {

    private static final Logger log = LoggerFactory.getLogger(ExploreSearchSqlLogTest.class);

    /** Hibernate 는 FULLTEXT 인덱스를 만들어 주지 않는다. 운영에서 쓰는 스크립트를 그대로 적용한다. */
    private static final String FULLTEXT_INDEX_SCRIPT = "mysql/post-start/01_add_places_search_fulltext.sql";

    private static final long CAFE_CONTENT_ID = 900_001L;
    private static final long PARK_CONTENT_ID = 900_002L;
    private static final long BEACH_CONTENT_ID = 900_003L;
    private static final String CAFE_TITLE = "연남동 골목 카페";
    private static final String PARK_TITLE = "남산 전망 산책로";
    private static final String BEACH_TITLE = "강릉 해변 전망대";
    private static final String CAT3_CAFE = "A01010100";
    private static final String CAT3_PARK = "A01010200";
    private static final String CAT3_BEACH = "A01010300";
    private static final String CONTENT_TYPE_ID = "12";
    private static final String OTHER_CONTENT_TYPE_ID = "14";
    private static final int EMOTION_CATEGORY_ID = 3;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private DataSource dataSource;

    @Autowired
    private JdbcTemplate jdbc;

    /**
     * 픽스처는 세 행이다. 각 필터가 <b>실제로 거르는지</b>까지 보려면 조건마다
     * "걸리는 행"과 "안 걸리는 행"이 모두 있어야 한다.
     *
     * <table border="1">
     *   <caption>픽스처</caption>
     *   <tr><th>행</th><th>search_text 에 "카페"</th><th>contentTypeId</th><th>cat3</th><th>감정 3 매핑</th></tr>
     *   <tr><td>{@link #CAFE_CONTENT_ID}</td><td>있음</td><td>12</td><td>A01010100</td><td>O</td></tr>
     *   <tr><td>{@link #PARK_CONTENT_ID}</td><td>없음</td><td>12</td><td>A01010200</td><td>O</td></tr>
     *   <tr><td>{@link #BEACH_CONTENT_ID}</td><td>없음</td><td>14</td><td>A01010300</td><td>X</td></tr>
     * </table>
     *
     * <p>PARK 행이 중요하다. 이 행은 Case 6 의 <b>키워드를 뺀 모든 조건</b>을 만족한다.
     * 그래서 {@code MATCH ... AGAINST} 절을 지우면 Case 6 이 1건이 아니라 2건이 되어 실패한다 —
     * 이슈 #26 의 완료 조건 3번("MATCH 절을 깨뜨리면 CI 가 실패한다")이 이 행에 걸려 있다.</p>
     */
    @BeforeEach
    void seedSearchFixture() {
        applyOperationalSqlScript(dataSource, FULLTEXT_INDEX_SCRIPT);

        jdbc.update("DELETE FROM cat3_category_mapping");
        jdbc.update("DELETE FROM place_trait_snapshots");
        jdbc.update("DELETE FROM places");

        insertPlace(CAFE_CONTENT_ID, CAFE_TITLE, CAT3_CAFE, CONTENT_TYPE_ID, "연남동 골목 카페 커피 로스팅");
        insertPlace(PARK_CONTENT_ID, PARK_TITLE, CAT3_PARK, CONTENT_TYPE_ID, "남산 전망 산책로 야경");
        insertPlace(BEACH_CONTENT_ID, BEACH_TITLE, CAT3_BEACH, OTHER_CONTENT_TYPE_ID, "강릉 해변 전망대 일출");

        jdbc.update("""
                INSERT INTO place_trait_snapshots (cat3, cat3name, short_desc1, short_desc2)
                VALUES (?, ?, ?, ?)
                """, CAT3_CAFE, "카페", "조용한 골목", "커피 향");

        jdbc.update("INSERT INTO cat3_category_mapping (category_id, cat3_code) VALUES (?, ?)",
                EMOTION_CATEGORY_ID, CAT3_CAFE);
        jdbc.update("INSERT INTO cat3_category_mapping (category_id, cat3_code) VALUES (?, ?)",
                EMOTION_CATEGORY_ID, CAT3_PARK);
    }

    private void insertPlace(long contentId, String title, String cat3, String contentTypeId, String searchText) {
        LocalDateTime now = LocalDateTime.of(2026, 1, 1, 0, 0);
        jdbc.update("""
                INSERT INTO places
                    (contentid, title, addr1, addr2, cat1, cat2, cat3, areacode, sigungucode,
                     contenttypeid, search_text, createdtime, modifiedtime, ugc_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """,
                contentId, title, "서울특별시 마포구", "연남동", "A01", "A0101", cat3,
                1, 1, contentTypeId, searchText, now, now);
    }

    @Test
    @DisplayName("Case 1 - 필터 없음")
    void search_case1_noFilters() throws Exception {
        performCase("Case 1 - no filters",
                get("/api/explore/places/search"))
                .andExpect(jsonPath("$.totalElements").value(3));
    }

    @Test
    @DisplayName("Case 2 - contentTypeId = 12")
    void search_case2_contentTypeId12() throws Exception {
        // BEACH 행만 contentTypeId=14 라 걸러진다.
        performCase("Case 2 - contentTypeId=12",
                get("/api/explore/places/search")
                        .param("contentTypeId", CONTENT_TYPE_ID))
                .andExpect(jsonPath("$.totalElements").value(2));
    }

    @Test
    @DisplayName("Case 3 - cat3 IN (...)")
    void search_case3_cat3In() throws Exception {
        // BEACH 행의 cat3 는 목록에 없다.
        performCase("Case 3 - cat3 IN (...)",
                get("/api/explore/places/search")
                        .param("cat3", CAT3_CAFE + "," + CAT3_PARK))
                .andExpect(jsonPath("$.totalElements").value(2));
    }

    @Test
    @DisplayName("Case 4 - emotionCategoryId = 3")
    void search_case4_emotionCategoryId3() throws Exception {
        // cat3_category_mapping 에 CAFE·PARK 의 cat3 만 감정 3 으로 매핑돼 있다.
        performCase("Case 4 - emotionCategoryId=3",
                get("/api/explore/places/search")
                        .param("emotionCategoryId", String.valueOf(EMOTION_CATEGORY_ID)))
                .andExpect(jsonPath("$.totalElements").value(2));
    }

    /**
     * MySQL FULLTEXT 경로. "카페"는 2글자라 {@code innodb_ft_min_token_size} 가 기본값 3 이면
     * 색인도 검색도 되지 않아 0건이 된다. 아래 단언이 그 상태를 잡는다.
     */
    @Test
    @DisplayName("Case 5 - q = 카페 (MySQL FULLTEXT)")
    void search_case5_keywordCafe() throws Exception {
        performCase("Case 5 - q=카페",
                get("/api/explore/places/search")
                        .param("q", "카페"))
                // 1건이어야 한다: 잡혀야 할 행을 잡고(=FULLTEXT 가 동작하고),
                // 잡히면 안 되는 행은 거른다(=MATCH 절이 실제로 필터로 쓰인다).
                .andExpect(jsonPath("$.totalElements").value(1))
                .andExpect(jsonPath("$.content.length()").value(1))
                .andExpect(jsonPath("$.content[0].contentid").value(CAFE_CONTENT_ID))
                .andExpect(jsonPath("$.content[0].title").value(CAFE_TITLE))
                // LEFT JOIN place_trait_snapshots 로 붙는 파생 필드까지 확인한다.
                .andExpect(jsonPath("$.content[0].cat3Name").value("카페"));
    }

    /**
     * 모든 조건 조합. {@code page=1} 이라 content 는 비지만(2페이지째),
     * {@code totalElements} 는 MATCH 절이 포함된 COUNT 쿼리 결과다.
     *
     * <p>PARK 행이 키워드를 뺀 나머지 조건을 전부 만족하므로, 이 1건 단언은 양쪽을 다 잡는다 —
     * FULLTEXT 가 죽으면 0, MATCH 절이 사라지면 2.</p>
     */
    @Test
    @DisplayName("Case 6 - 모든 조건 조합")
    void search_case6_allFilters() throws Exception {
        performCase("Case 6 - all filters",
                get("/api/explore/places/search")
                        .param("q", "카페")
                        .param("contentTypeId", CONTENT_TYPE_ID)
                        .param("cat3", CAT3_CAFE + "," + CAT3_PARK)
                        .param("emotionCategoryId", String.valueOf(EMOTION_CATEGORY_ID))
                        .param("page", "1")
                        .param("size", "20")
                        .param("sort", "recent"))
                .andExpect(jsonPath("$.totalElements").value(1))
                .andExpect(jsonPath("$.page").value(1))
                .andExpect(jsonPath("$.size").value(20));
    }

    private ResultActions performCase(String caseName,
                                      org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder request) throws Exception {
        log.info("");
        log.info("============================================================");
        log.info("Starting {}", caseName);
        log.info("Request: {}", request);
        log.info("============================================================");

        return mockMvc.perform(request)
                .andDo(print())
                .andExpect(status().isOk());
    }
}

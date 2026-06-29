package com.heattrip.heat_trip_backend.explore.web;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultHandlers.print;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = {
        "spring.jpa.show-sql=true",
        "spring.jpa.properties.hibernate.format_sql=true",
        "logging.level.org.hibernate.SQL=DEBUG",
        "logging.level.org.hibernate.orm.jdbc.bind=TRACE",
        "logging.level.org.springframework.transaction=TRACE"
})
class ExploreSearchSqlLogTest {

    private static final Logger log = LoggerFactory.getLogger(ExploreSearchSqlLogTest.class);

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("Case 1 - 필터 없음")
    void search_case1_noFilters() throws Exception {
        performCase("Case 1 - no filters",
                get("/api/explore/places/search"));
    }

    @Test
    @DisplayName("Case 2 - contentTypeId = 12")
    void search_case2_contentTypeId12() throws Exception {
        performCase("Case 2 - contentTypeId=12",
                get("/api/explore/places/search")
                        .param("contentTypeId", "12"));
    }

    @Test
    @DisplayName("Case 3 - cat3 IN (...)")
    void search_case3_cat3In() throws Exception {
        performCase("Case 3 - cat3 IN (...)",
                get("/api/explore/places/search")
                        .param("cat3", "A01010100,A01010200"));
    }

    @Test
    @DisplayName("Case 4 - emotionCategoryId = 3")
    void search_case4_emotionCategoryId3() throws Exception {
        performCase("Case 4 - emotionCategoryId=3",
                get("/api/explore/places/search")
                        .param("emotionCategoryId", "3"));
    }

    @Test
    @DisplayName("Case 5 - q = 카페")
    void search_case5_keywordCafe() throws Exception {
        performCase("Case 5 - q=카페",
                get("/api/explore/places/search")
                        .param("q", "카페"));
    }

    @Test
    @DisplayName("Case 6 - 모든 조건 조합")
    void search_case6_allFilters() throws Exception {
        performCase("Case 6 - all filters",
                get("/api/explore/places/search")
                        .param("q", "카페")
                        .param("contentTypeId", "12")
                        .param("cat3", "A01010100,A01010200")
                        .param("emotionCategoryId", "3")
                        .param("page", "1")
                        .param("size", "20")
                        .param("sort", "recent"));
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

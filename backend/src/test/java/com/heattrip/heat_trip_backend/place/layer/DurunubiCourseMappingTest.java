package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** 두루누비 코스 한 줄 → {@code Course} 와 카드 한 줄 — 이슈 #291. */
class DurunubiCourseMappingTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final String ITEM = """
            {"crsIdx":"T_ROUTE_1","crsKorNm":"서울숲 둘레길","routeIdx":"R1","crsDstnc":"12.3",
             "crsTotlRqrmHour":"240","crsLevel":"2","crsCycle":"순환","sigun":"서울 성동구",
             "gpxpath":"https://www.durunubi.kr/gpx/T_ROUTE_1.gpx","crsSummary":"한강을 끼고 도는 길"}
            """;

    @Test
    @DisplayName("코스 번호·이름·GPX 주소·거리·시간·난이도를 읽는다")
    void mapsACourse() throws Exception {
        DurunubiApiClient.Course course = DurunubiApiClient.toCourse(MAPPER.readTree(ITEM)).orElseThrow();

        assertThat(course.courseId()).isEqualTo("T_ROUTE_1");
        assertThat(course.name()).isEqualTo("서울숲 둘레길");
        assertThat(course.gpxUrl()).isEqualTo("https://www.durunubi.kr/gpx/T_ROUTE_1.gpx");
        assertThat(course.distanceKm()).isEqualTo(12.3);
        assertThat(course.minutes()).isEqualTo(240);
        assertThat(course.level()).isEqualTo(2);
        assertThat(course.sigun()).isEqualTo("서울 성동구");
    }

    @Test
    @DisplayName("GPX 주소나 이름이 없으면 버린다 — 선도 점도 만들 수 없다")
    void dropsACourseWithoutGpxOrName() throws Exception {
        assertThat(DurunubiApiClient.toCourse(MAPPER.readTree(
                ITEM.replace("\"gpxpath\":\"https://www.durunubi.kr/gpx/T_ROUTE_1.gpx\",", "")))).isEmpty();
        assertThat(DurunubiApiClient.toCourse(MAPPER.readTree(
                ITEM.replace("\"crsKorNm\":\"서울숲 둘레길\",", "")))).isEmpty();
    }

    @Test
    @DisplayName("카드 한 줄 — 거리 · 약 시간 · 난이도 · 순환. 모르는 값은 안 그린다")
    void summaryReadsLikeACard() throws Exception {
        DurunubiApiClient.Course course = DurunubiApiClient.toCourse(MAPPER.readTree(ITEM)).orElseThrow();
        assertThat(course.summary()).isEqualTo("12.3km · 약 4시간 · 보통 · 순환");

        DurunubiApiClient.Course ninety = DurunubiApiClient.toCourse(MAPPER.readTree(
                ITEM.replace("\"crsTotlRqrmHour\":\"240\"", "\"crsTotlRqrmHour\":\"90\"")
                        .replace("\"crsLevel\":\"2\"", "\"crsLevel\":\"1\"")
                        .replace("\"crsCycle\":\"순환\",", "")
                        .replace("\"crsDstnc\":\"12.3\"", "\"crsDstnc\":\"5\""))).orElseThrow();
        assertThat(ninety.summary()).isEqualTo("5km · 약 1시간 30분 · 쉬움");

        DurunubiApiClient.Course bare = DurunubiApiClient.toCourse(MAPPER.readTree(
                "{\"crsIdx\":\"X\",\"crsKorNm\":\"이름만\",\"gpxpath\":\"https://x/y.gpx\"}")).orElseThrow();
        assertThat(bare.summary()).isEmpty();
    }
}

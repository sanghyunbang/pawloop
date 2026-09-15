package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.TrailRoute;

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
    @DisplayName("카드의 '12.3km' 와 추천이 쓰는 숫자가 한 값에서 온다 (#539)")
    void theSummaryAndTheNumberComeFromOneValue() throws Exception {
        DurunubiApiClient.Course course = DurunubiApiClient.toCourse(MAPPER.readTree(ITEM)).orElseThrow();

        assertThat(course.summary()).contains("12.3km");
        assertThat(PlaceDto.metersOf(course.distanceKm()))
                .as("둘이 다른 값에서 오면 카드와 추천이 다른 말을 한다")
                .isEqualTo(12_300);
    }

    @Test
    @DisplayName("카탈로그 항목이 그 숫자를 싣는다 — 여기서 빠뜨리면 추천이 길이를 모른다 (#539)")
    void theCatalogEntryCarriesTheCourseLength() throws Exception {
        DurunubiApiClient.Course course = DurunubiApiClient.toCourse(MAPPER.readTree(ITEM)).orElseThrow();
        TrailRoute route = TrailRoute.builder()
                .courseId("T_ROUTE_1").name("서울숲 둘레길").pointCount(120).lengthM(12_000)
                .startLat(37.5445).startLng(127.0374).payload("[]")
                .fetchedAt(java.time.LocalDateTime.of(2026, 9, 15, 9, 0))
                .build();

        PlaceDto place = LayerCatalogService.toPlace(course, route);

        assertThat(place.contentId()).isEqualTo("trail:T_ROUTE_1");
        assertThat(place.source()).isEqualTo(PlaceDto.SOURCE_TRAIL);
        assertThat(place.lat()).isEqualTo(37.5445);
        assertThat(place.courseM())
                .as("이 자리가 비어 있던 동안 오늘의 코스는 '목표 2.0km' 를 적어 놓고 그냥 가까운 순이었다")
                .isEqualTo(12_300);
        assertThat(place.summary()).as("문장은 그대로다 — 지도 시트가 쓴다").contains("12.3km");
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

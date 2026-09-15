package com.heattrip.heat_trip_backend.place;

import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.layer.LocalTrailAsset;

import org.assertj.core.data.Offset;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 저장소에 넣어 둔 동네 길 자산이 쓸 만한가 — 이슈 #346.
 *
 * <h2>왜 자산을 테스트가 직접 읽나</h2>
 * <p>이 파일은 사람이 손으로 만드는 것이 아니라 {@code backend/tools/build_local_trails.py} 가
 * 지오코더를 태워 만든다. 지오코더가 한 번 이상하게 답하면 (0,0) 이나 일본 앞바다에 점이
 * 찍히고, <b>그 점은 지도에 그려지기 전까지 아무도 모른다.</b> 그래서 커밋된 결과를 여기서
 * 잰다 — 다음에 자산을 새로 만들 때 같은 검사가 다시 돈다.
 *
 * <h2>무엇이 왜 중요한가</h2>
 * <p>이 자산이 있는 이유는 하나다 — <b>산책로 칩이 동네 길을 보여 주는 것.</b> 그래서
 * "서울숲에서 8km 안에 몇 개가 잡히는가" 를 잰다. #328 에서 그 자리에 잡히던 것은
 * 19.7km 밖 DMZ 평화의 길 18km 코스였다.
 *
 * <p>네트워크를 타지 않는다. 클래스패스의 파일만 읽는다(#21).
 */
class LocalTrailAssetTest {

    private static final double SEOUL_FOREST_LAT = 37.5445;
    private static final double SEOUL_FOREST_LNG = 127.0374;

    private final List<PlaceDto> trails = new LocalTrailAsset(new ObjectMapper()).load();

    @Test
    @DisplayName("자산이 비어 있지 않다 — 비면 산책로 칩이 코리아둘레길로 돌아간다")
    void assetIsNotEmpty() {
        assertThat(trails)
                .as("""
                        data/local_trails.json 이 없거나 깨졌다. \
                        backend/tools/build_local_trails.py 로 다시 만든다.""")
                .hasSizeGreaterThan(1000);
    }

    @Test
    @DisplayName("좌표가 한반도 안이다 — 지오코더가 엉뚱하게 답한 점이 없다")
    void coordinatesAreInKorea() {
        List<PlaceDto> outside = trails.stream()
                .filter(p -> !(p.lat() >= 33.0 && p.lat() <= 38.7 && p.lng() >= 124.5 && p.lng() <= 132.0))
                .toList();

        assertThat(outside)
                .as("주소를 못 찾으면 (0,0) 이 되고, 그 점은 지도에 그려지기 전까지 안 보인다")
                .isEmpty();
    }

    @Test
    @DisplayName("서울숲 8km 안에 동네 길이 다섯 개 넘게 있다 — 이 자산의 존재 이유다")
    void seoulForestHasNeighbourhoodTrails() {
        List<PlaceDto> near = trails.stream()
                .filter(p -> haversineKm(SEOUL_FOREST_LAT, SEOUL_FOREST_LNG, p.lat(), p.lng()) <= 8)
                .toList();

        assertThat(near)
                .as("""
                        #328 에서 이 자리에 잡히던 것은 19.7km 밖 DMZ 평화의 길 18km 코스였다. \
                        여기가 다섯 아래로 떨어지면 자산이 잘못 만들어진 것이다.""")
                .hasSizeGreaterThan(5);
    }

    @Test
    @DisplayName("서울숲 8km 안 길이 중앙값이 6km 이하다 — 개수만으로는 '걸을 만한가' 를 못 잰다")
    void nearbyTrailsAreWalkable() {
        // 완료 조건이 개수와 중앙값 **둘 다**인 이유: 8km 안에 50km 짜리 종주 코스만 다섯 개
        // 있어도 개수 검사는 통과한다. 그건 이 자산이 고치려던 상태(#328)와 같다.
        List<Double> lengths = nearbyLengthsKm();

        assertThat(lengths)
                .as("길이를 읽을 수 있는 길이 8km 안에 있어야 중앙값을 낼 수 있다")
                .isNotEmpty();
        assertThat(median(lengths))
                .as("서울숲 8km 안 %d개의 길이 중앙값", lengths.size())
                .isLessThanOrEqualTo(6.0);
    }

    /** 서울숲 8km 안 동네 길의 길이(km). 요약의 맨 앞 토막이 길이다 — {@code 6.5km · …}. */
    private List<Double> nearbyLengthsKm() {
        return trails.stream()
                .filter(p -> haversineKm(SEOUL_FOREST_LAT, SEOUL_FOREST_LNG, p.lat(), p.lng()) <= 8)
                .map(PlaceDto::summary)
                .filter(s -> s != null && s.contains("km"))
                .map(s -> Double.parseDouble(s.substring(0, s.indexOf("km"))))
                .sorted()
                .toList();
    }

    private static double median(List<Double> sorted) {
        int n = sorted.size();
        return n % 2 == 1
                ? sorted.get(n / 2)
                : (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2;
    }

    @Test
    @DisplayName("두루누비와 id 가 안 겹친다 — 겹치면 한쪽이 지도에서 사라진다")
    void idsDoNotCollideWithDurunubi() {
        assertThat(trails).allSatisfy(p ->
                assertThat(p.contentId()).startsWith("trail:lt"));

        assertThat(trails.stream().map(PlaceDto::contentId).distinct().count())
                .as("같은 contentId 가 둘이면 앱이 하나만 그린다")
                .isEqualTo(trails.size());
    }

    @Test
    @DisplayName("산책로로 나간다 — 계약의 카테고리를 새로 만들지 않는다")
    void speaksTheExistingTrailCategory() {
        assertThat(trails).allSatisfy(p -> {
            assertThat(p.source()).isEqualTo(PlaceDto.SOURCE_TRAIL);
            assertThat(p.category()).isEqualTo(PlaceDto.SOURCE_TRAIL);
            assertThat(p.title()).isNotBlank();
        });
    }

    @Test
    @DisplayName("길이가 숫자로도 실린다 — 문장만으로는 추천이 못 센다 (#539)")
    void courseLengthComesAsANumber() {
        List<PlaceDto> withNumber = trails.stream().filter(PlaceDto::hasCourseLength).toList();

        assertThat(withNumber)
                .as("summary 의 \"3.4km\" 는 문장이라 셈에 못 쓴다. 이 값이 안 오면 오늘의 코스가"
                        + " \"목표 2.0km\" 를 적어 놓고 그냥 가까운 순으로 고른다(#539).")
                .hasSizeGreaterThan(trails.size() / 2);
        assertThat(withNumber).allSatisfy(p -> assertThat(p.courseM()).isPositive());
    }

    @Test
    @DisplayName("숫자와 문장이 같은 길이를 말한다 — 카드와 추천이 다른 말을 하면 안 된다 (#539)")
    void theNumberAgreesWithTheSentence() {
        List<PlaceDto> both = trails.stream()
                .filter(p -> p.hasCourseLength() && p.summary() != null && p.summary().contains("km"))
                .limit(200)
                .toList();

        assertThat(both).as("훑은 것이 없으면 이 검사는 언제나 초록이다").isNotEmpty();
        assertThat(both).allSatisfy(p -> {
            String head = p.summary().substring(0, p.summary().indexOf("km"));
            double fromSentence = Double.parseDouble(head.replaceAll("[^0-9.]", ""));
            assertThat(p.courseM() / 1000.0)
                    .as("%s — 문장 %s · 숫자 %dm", p.title(), p.summary(), p.courseM())
                    .isCloseTo(fromSentence, Offset.offset(0.05));
        });
    }

    @Test
    @DisplayName("요약이 길이부터 말한다 — 카드에서 먼저 보는 것이 그것이다")
    void summaryLeadsWithLength() {
        List<PlaceDto> withSummary = trails.stream().filter(p -> p.summary() != null).toList();

        assertThat(withSummary)
                .as("길이가 없는 행은 원본에도 없다 — 대부분은 있어야 한다")
                .hasSizeGreaterThan(trails.size() / 2);
        assertThat(withSummary).allSatisfy(p ->
                assertThat(p.summary()).matches("^[0-9].*|^약 .*|^[^0-9].*"));
    }

    private static double haversineKm(double aLat, double aLng, double bLat, double bLng) {
        double r = 6371.0;
        double dLat = Math.toRadians(bLat - aLat);
        double dLng = Math.toRadians(bLng - aLng);
        double h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(aLat)) * Math.cos(Math.toRadians(bLat))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * r * Math.asin(Math.sqrt(h));
    }
    @Test
    @DisplayName("요약에 경유지가 없다 — 화살표가 이어지다 잘리는 문장이 카드에 나갔다")
    void summaryHasNoWaypointChain() {
        // 원본의 구분자가 일곱 가지라(→ · - · ~ · , · -> · > · ∼) 어떤 기준으로 잘라도
        // 반쪽짜리 이름이 남는다. 그래서 카드에서는 아예 뺀다.
        assertThat(trails)
                .filteredOn(p -> p.summary() != null)
                .allSatisfy(p -> assertThat(p.summary())
                        .doesNotContain("→")
                        .doesNotContain("->")
                        .doesNotContain("…")
                        .doesNotContain("~"));
    }

    @Test
    @DisplayName("여덟 시간을 넘는 완주 시간은 안 적는다 — \"약 88시간\" 은 값이 깨진 것으로 읽힌다")
    void doesNotShowUnreasonableDurations() {
        assertThat(trails)
                .filteredOn(p -> p.summary() != null && p.summary().contains("시간"))
                .allSatisfy(p -> {
                    java.util.regex.Matcher m = java.util.regex.Pattern
                            .compile("약 (\\d+)시간").matcher(p.summary());
                    if (m.find()) {
                        assertThat(Integer.parseInt(m.group(1)))
                                .as("요약: %s", p.summary())
                                .isLessThanOrEqualTo(8);
                    }
                });
    }

    @Test
    @DisplayName("거리는 남는다 — 얼마나 긴 길인지는 말해 준다")
    void keepsTheLength() {
        assertThat(trails)
                .filteredOn(p -> p.summary() != null)
                .anySatisfy(p -> assertThat(p.summary()).contains("km"));
    }
}

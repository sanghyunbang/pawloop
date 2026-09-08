package com.heattrip.heat_trip_backend.place;

import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.layer.LocalTrailAsset;

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
}

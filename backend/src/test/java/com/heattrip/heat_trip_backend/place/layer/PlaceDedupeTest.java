package com.heattrip.heat_trip_backend.place.layer;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

/**
 * 겹치는 자리 정리의 규칙 — 이슈 #411. 스프링 없이 순수 함수만 본다.
 *
 * <p>좌표의 자: 위도 0.001° ≈ 111m. 33m ≈ 0.0003°, 75m ≈ 0.00068°, 250m ≈ 0.00225°.
 */
class PlaceDedupeTest {

    private static PlaceDto kto(String id, String title, double lat, double lng, String tel) {
        return new PlaceDto(id, title, PlaceDto.SOURCE_KTO, "12", "12", lat, lng, "주소",
                tel, "https://tong.visitkorea.or.kr/" + id + ".jpg", null);
    }

    private static PlaceDto playground(String id, String title, double lat, double lng, String tel) {
        return new PlaceDto(id, title, PlaceDto.SOURCE_PLAYGROUND, PlaceDto.SOURCE_PLAYGROUND, null,
                lat, lng, "주소", tel, null, null, null);
    }

    private static PlaceDto trail(String id, String title, double lat, double lng) {
        return new PlaceDto(id, title, PlaceDto.SOURCE_TRAIL, PlaceDto.SOURCE_TRAIL, null,
                lat, lng, "주소", null, null, null, "4.2km · 약 1시간");
    }

    @Test
    @DisplayName("놀이터가 관광공사 항목과 200m 안 같은 이름(공백 차이)이면 빠지고, 관광공사 항목에 놀이터가 옮겨 달린다")
    void playgroundLosesToKtoAndTransfersItsCategory() {
        PlaceDto lake = kto("200", "일산호수공원 반려견놀이터", 37.6640, 126.7660, null);
        PlaceDto mine = playground("playground:ovl", "일산호수공원 반려견 놀이터", 37.6643, 126.7660, "031-000-0000");

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(lake), List.of(), List.of(mine));

        assertThat(merged.layers()).as("우리 놀이터는 빠진다").isEmpty();
        assertThat(merged.dropped()).isEqualTo(1);
        PlaceDto kept = merged.kto().get(0);
        assertThat(kept.contentId()).isEqualTo("200");
        assertThat(kept.source()).isEqualTo(PlaceDto.SOURCE_KTO);
        assertThat(kept.category()).isEqualTo(PlaceDto.SOURCE_PLAYGROUND);
        assertThat(kept.contentTypeId()).as("앱은 contentTypeId 를 먼저 보므로 비워야 놀이터로 읽는다").isNull();
        assertThat(kept.categoryKey()).isEqualTo(PlaceDto.SOURCE_PLAYGROUND);
        assertThat(kept.image()).as("사진은 관광공사 것 그대로").isEqualTo("https://tong.visitkorea.or.kr/200.jpg");
        assertThat(kept.tel()).as("관광공사에 없는 전화는 우리 것을 옮긴다").isEqualTo("031-000-0000");
        assertThat(merged.overrides()).containsOnlyKeys("200");
        assertThat(merged.override(lake)).isSameAs(kept);
    }

    @Test
    @DisplayName("관광공사에 전화가 있으면 그것을 지킨다")
    void ktoPhoneWins() {
        PlaceDto lake = kto("200", "일산호수공원 반려견놀이터", 37.6640, 126.7660, "02-000-0000");
        PlaceDto mine = playground("playground:ovl", "일산호수공원 반려견 놀이터", 37.6643, 126.7660, "031-000-0000");

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(lake), List.of(), List.of(mine));

        assertThat(merged.kto().get(0).tel()).isEqualTo("02-000-0000");
    }

    @Test
    @DisplayName("동네 길은 빠지되 옮기지 않는다 — 자라섬째즈길에 밀린 자라섬은 산책로가 아니다")
    void localTrailLosesWithoutTransfer() {
        PlaceDto island = kto("300", "자라섬", 37.8195, 127.5470, null);
        PlaceDto mine = trail("trail:ltjazz", "자라섬째즈길", 37.81955, 127.5470);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(island), List.of(), List.of(mine));

        assertThat(merged.layers()).isEmpty();
        assertThat(merged.dropped()).isEqualTo(1);
        assertThat(merged.kto().get(0)).as("관광공사 항목은 손대지 않는다").isSameAs(island);
        assertThat(merged.overrides()).isEmpty();
    }

    @Test
    @DisplayName("두루누비 코스에 밀린 동네 길도 빠진다 — 두루누비는 그대로 남는다")
    void localTrailLosesToDurunubi() {
        PlaceDto durunubi = trail("trail:T_45", "해파랑길 45코스", 38.1000, 128.6000);
        PlaceDto mine = trail("trail:lt45", "해파랑길 45코스", 38.10068, 128.6000);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(), List.of(durunubi), List.of(mine));

        assertThat(merged.layers()).containsExactly(durunubi);
        assertThat(merged.dropped()).isEqualTo(1);
        assertThat(merged.overrides()).isEmpty();
    }

    @Test
    @DisplayName("이름이 같아도 200m 밖이면, 가까워도 이름이 다르면 둘 다 남는다")
    void farOrDifferentlyNamedPlacesBothSurvive() {
        PlaceDto ktoFar = kto("400", "세종호수공원", 36.5040, 127.2840, null);
        PlaceDto mineFar = trail("trail:ltfar", "세종호수공원 산책로", 36.50625, 127.2840);
        PlaceDto ktoNear = kto("401", "청주동물원", 36.6400, 127.5000, null);
        PlaceDto mineNear = playground("playground:near", "우암산 반려견 놀이터", 36.64005, 127.5000, null);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(ktoFar, ktoNear), List.of(), List.of(mineFar, mineNear));

        assertThat(merged.layers()).containsExactly(mineFar, mineNear);
        assertThat(merged.dropped()).isZero();
        assertThat(merged.kto()).containsExactly(ktoFar, ktoNear);
    }

    @Test
    @DisplayName("쇼핑 · 음식점 · 병원에는 안 진다 — 동네 길 '삼청동' 은 139m 안의 '은나무 삼청동점'(쇼핑)과 다른 곳이다")
    void trailsNeverYieldToShopsOrClinics() {
        PlaceDto shop = new PlaceDto("700", "은나무 삼청동점", PlaceDto.SOURCE_KTO, "38", "38",
                37.5830, 126.9820, "주소", null, "https://tong.visitkorea.or.kr/700.jpg", null);
        PlaceDto vet = new PlaceDto("vet:7", "삼청동 동물병원", PlaceDto.SOURCE_VET, PlaceDto.SOURCE_VET, null,
                37.5831, 126.9820, "주소", null, null, null, null);
        PlaceDto walk = trail("trail:ltsamcheong", "삼청동", 37.5832, 126.9820);
        PlaceDto park = playground("playground:cafe", "삼청동 반려견 놀이터", 37.5833, 126.9820, null);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(shop), List.of(vet), List.of(walk, park));

        assertThat(merged.layers()).containsExactly(vet, walk, park);
        assertThat(merged.dropped()).isZero();
        assertThat(merged.overrides()).isEmpty();
    }

    @Test
    @DisplayName("한 글자 이름은 포함으로 안 묶는다 — '숲' 은 모든 숲을 포함한다")
    void oneCharacterNamesNeverMatchByContainment() {
        PlaceDto forest = kto("500", "서울숲", 37.5445, 127.0374, null);
        PlaceDto mine = playground("playground:one", "숲", 37.5446, 127.0374, null);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(forest), List.of(), List.of(mine));

        assertThat(merged.layers()).containsExactly(mine);
        assertThat(merged.overrides()).isEmpty();
    }

    @Test
    @DisplayName("우리 것끼리는 안 묶는다 — 이웃한 놀이터 둘은 둘 다 진짜다")
    void ourAssetsNeverCollapseEachOther() {
        PlaceDto a = playground("playground:a", "호수공원 반려견 놀이터", 37.6640, 126.7660, null);
        PlaceDto b = playground("playground:b", "호수공원 반려견 놀이터 2", 37.6641, 126.7660, null);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(), List.of(), List.of(a, b));

        assertThat(merged.layers()).containsExactly(a, b);
        assertThat(merged.dropped()).isZero();
    }

    @Test
    @DisplayName("빈 입력은 그대로 나온다")
    void emptyInputsPassThrough() {
        PlaceDto place = kto("600", "서울숲", 37.5445, 127.0374, null);
        PlaceDto vet = new PlaceDto("vet:1", "성수 동물병원", PlaceDto.SOURCE_VET, PlaceDto.SOURCE_VET, null,
                37.5445, 127.0380, "주소", null, null, null, null);

        PlaceDedupe.Merged merged = PlaceDedupe.merge(List.of(place), List.of(vet), List.of());

        assertThat(merged.kto()).containsExactly(place);
        assertThat(merged.layers()).containsExactly(vet);
        assertThat(merged.overrides()).isEmpty();
        assertThat(merged.dropped()).isZero();
    }

    @Test
    @DisplayName("이름 정규화 — 공백 전부와 대소문자를 무시하고, 포함은 양쪽 다 본다")
    void nameNormalisationAndContainment() {
        assertThat(PlaceDedupe.normalize(" 반려견  놀이터 ")).isEqualTo("반려견놀이터");
        assertThat(PlaceDedupe.normalize("Dog Park")).isEqualTo("dogpark");
        assertThat(PlaceDedupe.sameName("세종호수공원", "세종호수공원산책로")).isTrue();
        assertThat(PlaceDedupe.sameName("세종호수공원산책로", "세종호수공원")).isTrue();
        assertThat(PlaceDedupe.sameName("세종호수공원", "청주동물원")).isFalse();
        assertThat(PlaceDedupe.sameName("", "청주동물원")).isFalse();
    }
}

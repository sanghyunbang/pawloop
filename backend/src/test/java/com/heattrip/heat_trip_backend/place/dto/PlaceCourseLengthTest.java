package com.heattrip.heat_trip_backend.place.dto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 코스 길이를 <b>숫자로도</b> 싣는다 — 이슈 #539.
 *
 * <h2>무엇이 있었나</h2>
 *
 * <p>{@code summary} 에 "12.3km · 약 4시간 · 보통" 이 있었지만 <b>문장이라 셈에 못 쓴다.</b>
 * 앱의 오늘의 코스가 "목표 2.0km" 를 카드에 적어 놓고도 그 숫자를 못 썼다 — 후보가 전부
 * 길이를 모르니 점수의 길이 항이 서로 상쇄되고, 남는 것은 현재 위치에서의 거리뿐이라
 * <b>그냥 가까운 순</b>이었다.
 *
 * <p>숫자는 원본에 있었다. 두루누비 {@code crsDstnc} 가 {@code Course.distanceKm} 으로 들어와
 * {@code summary()} 를 만드는 데만 쓰이고 버려졌다 — 그 자리는
 * {@code DurunubiCourseMappingTest} 가 잰다(패키지가 달라 여기서 부를 수 없다).
 */
class PlaceCourseLengthTest {

    @Test
    @DisplayName("킬로미터를 미터로 — 반올림한다")
    void convertsKilometresToMetres() {
        assertThat(PlaceDto.metersOf(4.2)).isEqualTo(4200);
        assertThat(PlaceDto.metersOf(12.35)).isEqualTo(12350);
        assertThat(PlaceDto.metersOf(0.0004)).as("0.4m — 반올림하면 0 이지만 값은 있었다").isZero();
    }

    @Test
    @DisplayName("모르는 값과 0 이하는 null — 0 으로 눕히면 '길이가 0인 코스' 가 된다")
    void unknownAndNonPositiveAreNull() {
        assertThat(PlaceDto.metersOf(null)).isNull();
        assertThat(PlaceDto.metersOf(0.0)).isNull();
        assertThat(PlaceDto.metersOf(-1.0)).isNull();
    }

    @Test
    @DisplayName("국토종주급 코스도 안 자른다 — 자르면 목표에 딱 맞는 코스로 둔갑한다")
    void doesNotClampVeryLongCourses() {
        assertThat(PlaceDto.metersOf(507.0)).isEqualTo(507_000);
    }

    @Test
    @DisplayName("거리를 채운 사본이 길이를 안 잃는다 — 서빙 직전에 부르는 자리다")
    void withDistanceKeepsTheCourseLength() {
        PlaceDto trail = new PlaceDto("trail:T_ROUTE_1", "서울숲 둘레길", PlaceDto.SOURCE_TRAIL,
                PlaceDto.SOURCE_TRAIL, null, 37.5445, 127.0374, "서울 성동구", null, null,
                null, "12.3km · 약 4시간", 12_300);

        assertThat(trail.withDistance(320).courseM())
                .as("여기서 떨어뜨리면 캐시에는 있는데 앱에는 안 가는 값이 된다")
                .isEqualTo(12_300);
        assertThat(trail.hasCourseLength()).isTrue();
    }

    @Test
    @DisplayName("길이를 모르는 출처는 편의 생성자가 null 로 채운다 — 병원 · 펫샵 · 놀이터")
    void sourcesWithoutACourseGetNull() {
        PlaceDto vet = new PlaceDto("vet:1", "행복동물병원", PlaceDto.SOURCE_VET,
                PlaceDto.SOURCE_VET, null, 37.5, 127.0, "서울", "02-000-0000", null, null, null);

        assertThat(vet.courseM()).isNull();
        assertThat(vet.hasCourseLength()).isFalse();
    }
}

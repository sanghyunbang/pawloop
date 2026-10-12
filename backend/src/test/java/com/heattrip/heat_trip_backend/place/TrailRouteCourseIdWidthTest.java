package com.heattrip.heat_trip_backend.place;

import com.heattrip.heat_trip_backend.place.entity.PetPlaceDetailRow;
import com.heattrip.heat_trip_backend.place.entity.TrailRoute;
import com.heattrip.heat_trip_backend.place.service.PlaceLoopService;
import jakarta.persistence.Column;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 추천 코스 번호가 {@code trail_route.course_id} 에 <b>늘</b> 들어가는가 — #782.
 *
 * <p>{@code course_id} 가 32자이던 동안 두루누비·놀이터 장소의 코스가 전부 그 칸을 넘어 500 이었다.
 * 실제 번호로 재는 검사는 {@code PlaceLoopIntegrationTest#longestRealIdsAreStored} 이고, 여기는 칸 크기의
 * <b>근거</b>를 잠근다 — 장소 번호 칸에 들어가는 번호라면 어떤 출처든, 가장 긴 길이에서도 코스 번호가
 * 들어간다. 장소 번호 칸을 넓히는 날 이 검사가 {@code course_id} 도 함께 넓히라고 말한다.
 */
class TrailRouteCourseIdWidthTest {

    @Test
    @DisplayName("장소 번호 칸에 들어가는 가장 긴 번호로, 가장 긴 길이의 코스 번호를 만들어도 course_id 에 들어간다")
    void longestPossibleCourseIdFits() throws Exception {
        int placeIdWidth = columnLength(PetPlaceDetailRow.class, "contentId");
        String longest = PlaceLoopService.courseIdOf("x".repeat(placeIdWidth), PlaceLoopService.MAX_LENGTH_M);

        assertThat(longest.length())
                .as("loop: + %d자 번호 + :%d = %d자", placeIdWidth, PlaceLoopService.MAX_LENGTH_M, longest.length())
                .isLessThanOrEqualTo(columnLength(TrailRoute.class, "courseId"));
    }

    @Test
    @DisplayName("course_id 칸의 크기는 TrailRoute.COURSE_ID_LENGTH 와 같다 — V4 마이그레이션이 그 값을 쓴다")
    void columnUsesTheNamedWidth() throws Exception {
        assertThat(columnLength(TrailRoute.class, "courseId")).isEqualTo(TrailRoute.COURSE_ID_LENGTH);
    }

    private static int columnLength(Class<?> entity, String field) throws NoSuchFieldException {
        return entity.getDeclaredField(field).getAnnotation(Column.class).length();
    }
}

package com.heattrip.heat_trip_backend.crew.dto;

import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewVisibility;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 크루 부분 수정 — 이슈 #417. ADR-0017 규약 4.
 *
 * <h2>{@link CrewRequest} 를 재사용하지 않는 이유</h2>
 * <p>그쪽은 <b>만들기용</b>이라 {@code name} 에 {@code @NotBlank} 가 붙어 있다. 그것을 PATCH 에
 * 쓰면 <b>계약대로는 부분 수정이 불가능해진다</b> — 정원만 8로 줄이려는 사람이 이름을 함께
 * 보내야 하고, 그 이름이 그 사이 남이 바꾼 값이면 되돌려 버린다. {@code PATCH /api/dogs} 가
 * 정확히 그 상태였다.
 *
 * <h2>{@code null} 과 빈 문자열이 다르다</h2>
 * <ul>
 *   <li>{@code null} — <b>안 바꾼다.</b> 필드를 아예 안 보낸 것이다.</li>
 *   <li>{@code ""} — <b>지운다.</b> 소개를 지우거나 동네를 떼는 유일한 방법이다. 안 나누면
 *       한 번 적은 소개를 영영 못 지운다.</li>
 * </ul>
 *
 * <p>계약에는 {@code minProperties: 1} 이 걸린다. 빈 본문 하나로 요청을 흘려보내면 아무것도
 * 안 바뀐 200 이 돌아가고, 부르는 쪽은 그것을 성공으로 읽는다.
 */
public record CrewPatch(
        @Size(min = 1, max = 30, message = "이름은 1자 이상 30자 이하여야 합니다.")
        String name,

        @Size(max = 200, message = "소개는 200자를 넘을 수 없습니다.")
        String intro,

        @Pattern(regexp = "^$|^[0-9]{10}$", message = "동네 코드는 열 자리 숫자여야 합니다.")
        String neighborhoodCode,

        CrewVisibility visibility,

        @Min(value = Crew.MIN_CAPACITY, message = "정원은 2명 이상이어야 합니다.")
        @Max(value = Crew.MAX_CAPACITY, message = "정원은 100명을 넘을 수 없습니다.")
        Integer capacity) {

    /** 하나라도 보냈는가. 서버가 {@code minProperties: 1} 을 실제로 지키는 자리다. */
    public boolean isEmpty() {
        return name == null && intro == null && neighborhoodCode == null
                && visibility == null && capacity == null;
    }
}

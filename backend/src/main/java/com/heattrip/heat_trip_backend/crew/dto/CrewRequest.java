package com.heattrip.heat_trip_backend.crew.dto;

import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewVisibility;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 계약의 {@code CrewInput} — 이슈 #417.
 *
 * @param neighborhoodCode 행정동 코드 열 자리. <b>안 주면 내 동네</b>를 쓴다(#342) —
 *                         모임을 만드는 사람은 대개 자기 동네에 만든다. 내 동네도 없으면
 *                         동네 없는 크루가 되고, 그때는 우리 동네 목록에 안 뜬다
 * @param visibility       안 주면 {@code invite} 다 — 처음부터 아무나 들어오면 관리가
 *                         안 된다({@link CrewVisibility} javadoc)
 * @param capacity         안 주면 {@value Crew#DEFAULT_CAPACITY} 명
 */
public record CrewRequest(
        @NotBlank(message = "크루 이름을 적어 주세요.")
        @Size(max = 30, message = "이름은 30자를 넘을 수 없습니다.")
        String name,

        @Size(max = 200, message = "소개는 200자를 넘을 수 없습니다.")
        String intro,

        @Pattern(regexp = "^$|^[0-9]{10}$", message = "동네 코드는 열 자리 숫자여야 합니다.")
        String neighborhoodCode,

        CrewVisibility visibility,

        @Min(value = Crew.MIN_CAPACITY, message = "정원은 2명 이상이어야 합니다.")
        @Max(value = Crew.MAX_CAPACITY, message = "정원은 100명을 넘을 수 없습니다.")
        Integer capacity) {
}

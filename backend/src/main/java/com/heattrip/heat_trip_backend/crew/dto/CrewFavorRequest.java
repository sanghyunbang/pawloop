package com.heattrip.heat_trip_backend.crew.dto;

import com.heattrip.heat_trip_backend.crew.entity.CrewFavor;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavorSlot;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * 계약의 {@code CrewFavorInput} — 이슈 #417.
 *
 * <p><b>금액도 기간도 없다.</b> 이슈가 그은 선이다 — 돈이 붙으면 우리가 중개자가 된다.
 * "두 시간만" 같은 말은 {@link #note} 에 사람 말로 적힌다.
 *
 * @param dogId 어느 아이를 맡기나. <b>내 아이여야 한다</b> — 아니면 404 다. 없어도 된다
 */
public record CrewFavorRequest(
        @NotNull(message = "언제 부탁할지 골라 주세요.")
        LocalDate onDate,

        @NotNull(message = "시간대를 골라 주세요.")
        CrewFavorSlot slot,

        Long dogId,

        @Size(max = CrewFavor.MAX_NOTE_LENGTH, message = "한 줄은 200자를 넘을 수 없습니다.")
        String note) {
}

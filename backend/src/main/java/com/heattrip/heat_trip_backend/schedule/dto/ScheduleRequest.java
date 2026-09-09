package com.heattrip.heat_trip_backend.schedule.dto;

import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 계약의 {@code ScheduleInput} — 이슈 #418.
 *
 * @param ownerKind 일정의 주인이 어느 도메인인가. {@code room} 은 크루(#417)가 설 때까지
 *                  <b>거절한다</b> — 값만 미리 열어 두었다
 * @param ownerRef  그 도메인의 id. 소유권은 서비스가 확인한다
 * @param dogId     어느 아이 것인가. <b>{@code ownerRef} 와 별개다</b> — "가족 소유인데 보리 것"
 *                  이 흔하다. 없어도 된다("사료 주문")
 * @param atTime    시각. <b>없어도 된다</b> — "이번 주말 목욕". 0시로 채우지 않는다
 * @param assignee  맡기로 한 사람의 id. <b>없어도 된다</b> — 정하지 않은 일도 적어 둔다
 */
public record ScheduleRequest(
        @NotNull(message = "일정 주인이 필요합니다.")
        ScheduleOwnerKind ownerKind,

        @NotNull(message = "일정 주인의 식별자가 필요합니다.")
        Long ownerRef,

        Long dogId,

        @NotNull(message = "일정 종류가 필요합니다.")
        ScheduleKind kind,

        @NotBlank(message = "제목을 적어 주세요.")
        @Size(max = 100, message = "제목은 100자를 넘을 수 없습니다.")
        String title,

        @Size(max = 500, message = "메모는 500자를 넘을 수 없습니다.")
        String memo,

        @NotNull(message = "날짜가 필요합니다.")
        LocalDate onDate,

        LocalTime atTime,

        Long assignee) {
}

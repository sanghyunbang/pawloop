package com.heattrip.heat_trip_backend.schedule.dto;

import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleStatus;

import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 계약의 {@code ScheduleUpdate} — 이슈 #418.
 *
 * <h2>잠금 값({@code version})이 여기 없다</h2>
 * <p>{@code version} 은 <b>쿼리로 받는다</b>({@code ?version=3}). 이 본문이 부분 수정이기
 * 때문이다 — ADR-0017 규약 4 는 {@code PATCH} 본문 스키마에 {@code required} 를 두지 말라고
 * 하고({@code ContractConventionsTest} 가 그것을 잰다), 그 규약은 "생성 스키마를 재사용하면
 * 부분 수정이 계약대로는 불가능해진다" 는 실제 사고에서 나왔다.
 *
 * <p>그런데 잠금 값은 <b>반드시 있어야 한다</b> — 선택으로 두면 앱이 안 보내는 순간 잠금이
 * 사라지고, 그때부터 뒤에 온 편집이 앞의 것을 조용히 덮는다. 본문에 두면 둘 중 하나를 어겨야
 * 해서, 필수인 쪽을 <b>본문 밖으로</b> 냈다. 계약이 {@code required: true} 로 정직하게 적을 수
 * 있는 자리다.
 *
 * <p>헤더({@code If-Match})가 더 표준이지만 그러려면 응답에 {@code ETag} 를 함께 내야 하고,
 * 이 리소스는 잠금 값을 이미 본문 필드로 내고 있다 — 앱이 그대로 되돌려 보내는 쪽이 짧다.
 *
 * <h2>주인은 못 바꾼다</h2>
 * <p>{@code ownerKind}·{@code ownerRef} 가 여기 없다. 아이 일정을 가족 일정으로 옮기는 것은
 * <b>권한이 바뀌는 일</b>이라, 고치기와 같은 문으로 두면 그 검사를 빠뜨리기 쉽다. 필요해지면
 * 별도 경로로 연다.
 *
 * @param status 안 보내면 상태를 안 바꾼다. 보내면 그것만 바꿔도 된다
 */
public record ScheduleUpdateRequest(
        Long dogId,

        ScheduleKind kind,

        @Size(max = 100, message = "제목은 100자를 넘을 수 없습니다.")
        String title,

        @Size(max = 500, message = "메모는 500자를 넘을 수 없습니다.")
        String memo,

        LocalDate onDate,

        LocalTime atTime,

        Long assignee,

        ScheduleStatus status) {
}

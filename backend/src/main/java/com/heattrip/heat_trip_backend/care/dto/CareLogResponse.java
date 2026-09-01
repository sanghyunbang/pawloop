package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;

import java.time.LocalDateTime;

/**
 * 케어 기록 하나 — 계약({@code openapi.yaml})의 {@code CareLog} 다. 이슈 #76.
 *
 * @param dogId 오늘은 <b>항상 {@code null}</b> 이다. {@code dog} 표는 #145 에서 생겼지만
 *              이 컬럼을 잇는 것은 아직 안 했다 — 이유는 {@link CareLog} 의 javadoc 이고
 *              이슈 <b>#154</b> 가 소유한다. 필드를 계약에 미리 둔 것은 잇는 날 앱이
 *              스키마를 바꾸지 않아도 되게 하려는 것이다
 * @param type  {@code water|meal|walk|med|vet}. {@link CareType} 가 소문자 그대로 직렬화한다
 */
public record CareLogResponse(
        long id,
        Long dogId,
        Long groupId,
        CareType type,
        CareDoerResponse doneBy,
        LocalDateTime occurredAt,
        String memo) {

    public static CareLogResponse of(CareLog log) {
        return new CareLogResponse(
                log.getId(),
                log.getDogId(),
                log.groupId(),
                log.getType(),
                CareDoerResponse.of(log.getDoneBy()),
                log.getOccurredAt(),
                log.getMemo());
    }
}

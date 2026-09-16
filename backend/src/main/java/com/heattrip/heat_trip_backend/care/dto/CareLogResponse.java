package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;

import com.heattrip.heat_trip_backend.config.ClockConfig;

import java.time.Instant;

/**
 * 케어 기록 하나 — 계약({@code openapi.yaml})의 {@code CareLog} 다. 이슈 #76.
 *
 * @param dogId <b>2026-09-15(#563)부터 실제로 채워진다.</b> 쓰기 경로가 {@code dogId} 를 받고
 *              {@code DogOwnership.requireInFamilyEntity} 로 그 집 아이인지 확인해 넣는다.
 *
 *              <p><b>그 전에 쌓인 행은 여전히 {@code null} 이다</b> — 어느 아이였는지 아무도
 *              모르는 값이라 지어내 채우지 않았다. 그래서 {@code ?dogId=} 로 걸러도 {@code null}
 *              인 행은 함께 나온다({@code CareService.matchesDog}): 빼면 어제 준 밥이 화면에서
 *              사라지고, 사라지면 "아직" 으로 읽혀 한 번 더 주게 된다
 * @param type  {@code water|meal|walk|med|vet|poop|pee}. {@link CareType} 가 소문자 그대로 직렬화한다
 * @param occurredAt <b>{@code Instant} 다 — {@code LocalDateTime} 이 아니다.</b> 이슈 #209.
 *
 *              <p>Jackson 이 {@code LocalDateTime} 을 <b>오프셋 없이</b> 직렬화하는데
 *              ({@code "2026-09-03T00:30:00"}) 계약은 {@code format: date-time} 이라고
 *              선언했고 그건 RFC3339 오프셋이 있어야 성립하는 형식이다. 앱의
 *              {@code DateTime.tryParse} 는 오프셋 없는 문자열을 <b>기기 지역 시각</b>으로
 *              읽으므로, 해외에 있는 가족이 보면 케어 시각이 그 차이만큼 어긋난다.
 *              {@code WalkResponse}·{@code PostResponse} 가 같은 이유로 {@code Instant} 다.
 *
 *              <p>컬럼에 담긴 값은 <b>{@link ClockConfig#SERVICE_ZONE} 의 로컬 시각</b>이다 —
 *              그 존에서 인스턴트로 세운다. 존이 빈에 박혀 있어서 이 변환이 정확하다.
 */
public record CareLogResponse(
        long id,
        Long dogId,
        Long groupId,
        CareType type,
        CareDoerResponse doneBy,
        Instant occurredAt,
        String memo) {

    public static CareLogResponse of(CareLog log) {
        return new CareLogResponse(
                log.getId(),
                log.dogId(),
                log.groupId(),
                log.getType(),
                CareDoerResponse.of(log.getDoneBy()),
                log.getOccurredAt().atZone(ClockConfig.SERVICE_ZONE).toInstant(),
                log.getMemo());
    }
}

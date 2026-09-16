package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.CareTime;
import com.heattrip.heat_trip_backend.care.entity.CareItem;
import com.heattrip.heat_trip_backend.care.entity.CareType;

import java.time.Instant;

/**
 * 그 집이 챙기는 일 하나 — 계약({@code openapi.yaml})의 {@code CareItem} 다. 이슈 #560.
 *
 * @param dogId      그 아이에게만 하는 일이면 그 아이, <b>비어 있으면 모든 아이</b>다. 물 · 밥 ·
 *                   산책은 비어 있고 {@code 심장사상충 약} 은 한 아이를 고른다
 * @param systemType 기본 일곱이면 그 종류, 직접 만든 것이면 <b>비어 있다</b>. 앱이 이 값으로
 *                   "오늘 몇 번" 을 어떻게 세는지 가른다 — 있으면 {@code careLog.type} 으로,
 *                   없으면 {@code careLog.careItemId} 로. 규칙이 두 곳에 생기는 것 아니냐면,
 *                   <b>맞다</b> — 그래서 조각 2 의 다음 PR 이 {@code careLog} 응답에 그 답을
 *                   실어 앱이 세지 않게 한다
 * @param dailyTarget 하루 몇 번. 비어 있으면 횟수만 세고, 있으면 화면이 {@code 1/2} 로 그린다
 * @param archivedAt 접은 시각. <b>비어 있으면 카드에 뜬다.</b> 접힌 것도 목록에 오는 이유는
 *                   고치기 화면이 "다시 켜기" 를 그려야 하기 때문이다
 */
public record CareItemResponse(
        long id,
        Long dogId,
        String name,
        String icon,
        CareType systemType,
        Integer dailyTarget,
        int sortOrder,
        Instant archivedAt) {

    public static CareItemResponse of(CareItem item) {
        return new CareItemResponse(
                item.getId(),
                item.getDog() == null ? null : item.getDog().getId(),
                item.getName(),
                item.getIcon(),
                item.getSystemType(),
                item.getDailyTarget(),
                item.getSortOrder(),
                // 컬럼은 UTC 로 눕혀 담겼다(CareItem 의 @PrePersist) — 세울 때도 같은 존이다.
                // CareLogResponse 가 SERVICE_ZONE 으로 세우는 것과 다른 이유는 거기 occurred_at
                // 이 "사람의 하루" 라 서버 시계의 벽시계이기 때문이다(CareTime javadoc).
                CareTime.toInstant(item.getArchivedAt()));
    }
}

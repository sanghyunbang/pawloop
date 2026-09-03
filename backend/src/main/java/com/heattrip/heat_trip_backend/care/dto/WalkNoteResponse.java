package com.heattrip.heat_trip_backend.care.dto;

import com.heattrip.heat_trip_backend.care.entity.WalkNote;

import com.heattrip.heat_trip_backend.config.ClockConfig;

import java.time.Instant;

/**
 * 산책 주의사항 한 장 — 계약({@code openapi.yaml})의 {@code WalkNote} 다. 이슈 #76.
 *
 * <h2>아직 아무도 안 썼으면 404 가 아니라 빈 본문이다</h2>
 * <p>"주의사항이 아직 없다" 는 <b>정상 상태</b>다. 404 로 답하면 앱은 오류 화면과 빈 화면을
 * 구별하려고 상태 코드로 분기해야 하고, 네트워크 실패와 "아직 없음" 이 같은 자리에서 만난다.
 * 그래서 {@link #empty} 를 돌려준다 — {@code body} 는 빈 문자열, {@code updatedBy}·
 * {@code updatedAt} 은 {@code null} 이다.
 *
 * <p><b>{@code id} 를 싣지 않는다.</b> 그룹당 한 장이라 그 id 로 갈 수 있는 경로가 없다.
 * 아무 데도 못 쓰는 식별자를 계약에 두면 앱이 그걸 키로 삼는다.
 *
 * <h2>{@code null} 과 {@code 알 수 없음} 은 다른 상태다</h2>
 * <p>{@code updatedBy} 가 JSON {@code null} 인 것은 <b>{@link #empty} 하나뿐</b>이다 — 그룹에
 * 행 자체가 없는, 아직 아무도 안 쓴 상태다. 메모는 있는데 <b>쓴 사람이 탈퇴한</b> 경우는
 * {@code CareDoerResponse.WITHDRAWN}({@code 알 수 없음})으로 나간다. 둘을 같은 모양으로
 * 뭉개면 "가족이 쓴 안전 메모" 와 "빈 그룹" 이 화면에서 구별되지 않는다.
 *
 * @param updatedBy 마지막으로 고친 사람. 아직 아무도 안 썼으면 {@code null},
 *                  고친 사람이 탈퇴했으면 {@code 알 수 없음}
 * @param updatedAt <b>{@code Instant} 다</b> — 이유는 {@link CareLogResponse#occurredAt}
 *                  javadoc(이슈 #209). 컬럼 값은 {@link ClockConfig#SERVICE_ZONE} 의 로컬
 *                  시각이라 그 존에서 인스턴트로 세운다.
 */
public record WalkNoteResponse(
        long groupId,
        String body,
        CareDoerResponse updatedBy,
        Instant updatedAt) {

    public static WalkNoteResponse of(WalkNote note) {
        return new WalkNoteResponse(
                note.getGroup().getId(),
                note.getBody(),
                CareDoerResponse.of(note.getUpdatedBy()),
                note.getUpdatedAt().atZone(ClockConfig.SERVICE_ZONE).toInstant());
    }

    /** 아직 한 번도 쓰이지 않은 그룹의 답. */
    public static WalkNoteResponse empty(long groupId) {
        return new WalkNoteResponse(groupId, "", null, null);
    }
}

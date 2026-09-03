package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.moderation.Reports;

import jakarta.validation.constraints.NotBlank;

/**
 * 신고 요청 — 계약의 {@code ReportInput}. 이슈 #166.
 *
 * <h2>{@code reason} 값은 여기서 검증하지 않는다</h2>
 * <p>Bean Validation 으로 하면 실패가 400 이 되지만 <b>어떤 값이 유효한지</b>를 못 말한다.
 * {@code CommunityService} 가 목록과 함께 던져 메시지에 실린다 — {@code board} 가 같은
 * 이유로 같은 자리에서 검증된다.
 *
 * <p><b>모르는 값을 {@code other} 로 눕히지 않는다.</b> 앱의 오타가 조용히 통과하면
 * 운영자가 세는 숫자가 소리 없이 틀어진다.
 *
 * <h2>{@code memo} 는 넘쳐도 400 이 아니다</h2>
 * <p>{@value Reports#MAX_MEMO_LENGTH} 자를 넘으면 <b>잘린다.</b> 거절하면 사용자가 쓴 신고가
 * 통째로 사라지는데, 잘린 메모로도 운영자의 판단에는 충분하다 — 채팅 신고가 같은 판단을
 * 이미 했다. 그래서 여기에 {@code @Size} 가 없다.
 */
public record ReportRequest(

        @NotBlank(message = "신고 사유를 골라 주세요.")
        String reason,

        String memo) {
}

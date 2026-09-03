package com.heattrip.heat_trip_backend.chat;

import java.time.Instant;

/**
 * 발급된 초대코드 하나를 chat 밖으로 내보내는 모양 — 이슈 #75.
 *
 * <p><b>시각은 {@link Instant} 다.</b> 이 record 는 뷰이면서 <b>그대로 응답 본문</b>이다 —
 * {@code ChatInviteController.issue} 가 이것을 돌려준다. {@code LocalDateTime} 이면 잭슨이
 * 오프셋 없이 내고, 계약의 {@code format: date-time} 은 RFC3339 오프셋을 요구한다. 컬럼
 * 값은 UTC 이고 세우는 것은 {@link ChatTime} 이다(#248).
 *
 * <p>이 셋은 #248 이 세던 일곱에 <b>없었다</b> — 응답 DTO 가 아니라 뷰라서 목록에서
 * 빠졌다. 계약에는 {@code expiresAt}·{@code revokedAt}·{@code createdAt} 셋 다
 * {@code format: date-time} 으로 적혀 있다({@code revokedAt} 은 이 뷰에 없다).
 *
 * @param expiresAt {@code null} 이면 무기한. 기본값은 {@link ChatLimits#inviteTtl(long)} 이 답한다
 * @param maxUses   {@code null} 이면 무제한. 기본값은 {@link ChatLimits#maxInviteUses(long)} 이 답한다
 */
public record ChatInviteView(
        String code,
        long roomId,
        Instant expiresAt,
        Integer maxUses,
        int usedCount,
        Instant createdAt) {
}

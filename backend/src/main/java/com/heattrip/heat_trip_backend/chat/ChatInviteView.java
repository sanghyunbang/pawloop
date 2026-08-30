package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 발급된 초대코드 하나를 chat 밖으로 내보내는 모양 — 이슈 #75.
 *
 * @param expiresAt {@code null} 이면 무기한. 기본값은 {@link ChatLimits#inviteTtl(long)} 이 답한다
 * @param maxUses   {@code null} 이면 무제한. 기본값은 {@link ChatLimits#maxInviteUses(long)} 이 답한다
 */
public record ChatInviteView(
        String code,
        long roomId,
        LocalDateTime expiresAt,
        Integer maxUses,
        int usedCount,
        LocalDateTime createdAt) {
}

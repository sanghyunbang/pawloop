package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 메시지가 저장됐다 — {@code ChatRoomService.postMessage} 가 저장 트랜잭션 안에서 발행한다.
 *
 * <p>듣는 쪽은 {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받아야 한다 — 커밋 전에 받으면
 * 롤백된 메시지의 알림이 나간다. chat 은 누가 듣는지 모른다(ADR-0011 결정 4 — 화살표는 한쪽이다).
 *
 * @param preview 본문의 앞부분. 알림 미리보기용이고 전문이 아니다
 */
public record ChatMessagePosted(
        long roomId,
        String roomName,
        long roomSeq,
        long messageId,
        long senderUserId,
        String senderName,
        String preview,
        LocalDateTime postedAt) {
}

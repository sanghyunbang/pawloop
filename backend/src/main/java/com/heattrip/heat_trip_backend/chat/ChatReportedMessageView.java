package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 신고에 딸린 메시지 사본 하나를 {@code chat} 밖으로 내보내는 모양 — 이슈 #82.
 *
 * <p><b>원본이 아니라 사본이다.</b> 원본이 지워진 뒤에도 이 값들은 그대로 나온다 —
 * 그게 신고 기록의 존재 이유다.
 *
 * @param senderName 보낸 <b>시점</b>의 이름. 지금 {@code users} 에 있는 이름이 아니다 —
 *                   신고를 훑는 시점에는 닉네임이 이미 바뀌어 있을 수 있다
 */
public record ChatReportedMessageView(
        long roomSeq,
        long senderUserId,
        String senderName,
        String body,
        String contentType,
        LocalDateTime sentAt) {
}

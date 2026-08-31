package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 메시지 하나를 chat 밖으로 내보내는 모양 — 이슈 #78.
 *
 * <h2>{@code senderName} 이 아니라 {@link #senderNameAtSendTime} 인 이유</h2>
 * <p>이름을 두 번 헷갈리지 않게 하려고 필드 이름에 시제를 박았다. <b>응답에 실을 이름은
 * 이 값이 아니다.</b> 응답의 이름은 지금 {@code users} 에 있는 이름이고(닉네임을 바꾸면
 * 과거 메시지도 따라 바뀐다 — #78 완료 조건 4), 탈퇴해서 없으면 "알 수 없음" 이다
 * (완료 조건 3). 그 해석은 chat 밖에서 한다 — {@code ChatSenderNames} 가 그 자리다.
 *
 * <p>이 값은 <b>방 안의 사람들이 그때 실제로 본 이름</b>이다. 신고를 받아 발신자의 메시지를
 * 훑을 때 "무슨 이름으로 그 말을 했는가" 를 남기는 것이 목적이고, 그래서 밖으로 내보내되
 * 이름으로 구분해 둔다({@link com.heattrip.heat_trip_backend.chat.entity.ChatMessage} javadoc).
 *
 * <p>{@code nickname} 이 없는 것은 {@link ChatMemberView} 와 같은 이유다 — 그건
 * {@code users} 의 값이고 chat 은 사용자를 id 로만 안다(ADR-0011 결정 4).
 *
 * @param deletedAt 소프트 삭제 시각. <b>{@code null} 이 아니어도 조회에서 빠지지 않는다</b> —
 *                  톰스톤이다. 거르면 그 {@code roomSeq} 가 클라이언트에 도달하지 않아
 *                  읽음 커서가 넘지 못하고 미읽음 뱃지가 영원히 남는다(ADR-0011)
 */
public record ChatMessageView(
        long id,
        long roomId,
        long roomSeq,
        long senderUserId,
        String senderNameAtSendTime,
        String body,
        String contentType,
        String clientMsgId,
        LocalDateTime createdAt,
        LocalDateTime deletedAt) {
}

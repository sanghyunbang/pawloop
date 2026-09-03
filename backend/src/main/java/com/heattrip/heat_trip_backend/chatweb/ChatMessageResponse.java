package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessageView;
import com.heattrip.heat_trip_backend.chat.ChatTime;

import java.time.Instant;

/**
 * 계약({@code openapi.yaml})의 {@code ChatMessage} 모양 — 이슈 #78.
 *
 * <h2>{@code senderName} 이 여기서 <b>바뀐다</b> — 그게 이 레코드가 있는 이유다</h2>
 * <p>{@link ChatMessageView#senderNameAtSendTime()} 는 <b>보낸 시점의 스냅샷</b>이고,
 * 계약의 {@code senderName} 은 <b>지금 {@code users} 에 있는 이름</b>이다(#78 완료 조건 3·4 —
 * 닉네임을 바꾸면 과거 메시지도 따라 바뀌고, 탈퇴하면 "알 수 없음" 이다). 두 값이 같은
 * 이름으로 불리면 옮기는 자리에서 반드시 한 번은 헷갈린다. 그래서 chat 쪽 필드에는 시제를
 * 박아 두었고, 계약의 이름으로 되돌리는 것은 여기 한 곳이다.
 *
 * <p>{@link #of(ChatMessageView, String)} 가 이름을 <b>인자로 받는</b> 것도 같은 이유다 —
 * 이 레코드는 {@code users} 를 모르고, 이름을 만드는 것은 {@link ChatSenderNames} 다.
 *
 * <h2>{@code clientMsgId} 를 싣지 않는다</h2>
 * <p>계약의 {@code ChatMessage} 스키마에 없다. 멱등키는 클라이언트가 만들어 보낸 값이라
 * 돌려줄 이유가 없고, 실으면 같은 방의 다른 사람에게 남의 키가 보인다.
 *
 * <h2>{@code hiddenByBlock} 은 <b>읽는 사람마다 다른 값</b>이다</h2>
 * <p>같은 메시지가 어떤 사람에게는 {@code true} 고 다른 사람에게는 {@code false} 다 —
 * 가리기는 내 화면에서만 접는 것이기 때문이다(#82). 그래서 이 값은 캐시할 수 없고,
 * 조립할 때마다 <b>읽는 사람</b>을 알아야 한다.
 *
 * <p>본문을 지워서 내리지 않는다. 가려진 자리에 "보기" 가 있어서, 지워 내리면 그것을 누를
 * 때 요청이 한 번 더 필요해진다({@code Blocks} javadoc).
 *
 * <h2>시각은 {@link java.time.Instant} 다 — 오프셋이 붙어야 계약이 성립한다</h2>
 * <p>계약이 {@code format: date-time} 이라고 선언했고 그건 RFC3339 <b>오프셋</b>이 있어야
 * 성립한다. {@code LocalDateTime} 을 그대로 실으면 잭슨이 {@code "2026-09-03T00:25:33.92"}
 * 로 낸다 — 앱의 {@code DateTime.tryParse} 는 그것을 <b>기기 지역 시각</b>으로 읽으므로
 * 해외에 있는 가족이 보면 그만큼 어긋난 시각이 그려진다(#248).
 *
 * <p>컬럼에 담긴 값은 UTC 다 — 이유는 {@link ChatTime}. 세우는 것도 그 클래스다.
 *
 * @param deletedAt 소프트 삭제 시각. <b>{@code null} 이 아니어도 목록에서 빠지지 않는다</b> —
 *                  톰스톤이다. 본문을 가리는 것은 화면의 일이다(ADR-0011)
 * @param hiddenByBlock 읽는 사람이 이 발신자를 가렸는가. <b>목록에서 빼지 않는 이유</b>는
 *                  {@code deletedAt} 과 같다 — 빼면 그 {@code roomSeq} 가 도달하지 않아
 *                  미읽음 뱃지가 영원히 남는다
 */
public record ChatMessageResponse(
        long id,
        long roomId,
        long roomSeq,
        long senderUserId,
        String senderName,
        String contentType,
        String body,
        Instant createdAt,
        Instant deletedAt,
        boolean hiddenByBlock) {

    static ChatMessageResponse of(ChatMessageView message, String senderName) {
        return of(message, senderName, false);
    }

    static ChatMessageResponse of(ChatMessageView message, String senderName,
                                  boolean hiddenByBlock) {
        return new ChatMessageResponse(message.id(), message.roomId(), message.roomSeq(),
                message.senderUserId(), senderName, message.contentType(), message.body(),
                ChatTime.toInstant(message.createdAt()),
                ChatTime.toInstant(message.deletedAt()), hiddenByBlock);
    }
}

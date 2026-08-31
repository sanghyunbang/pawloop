package com.heattrip.heat_trip_backend.chatweb;

/**
 * 전송 요청 본문 — 계약({@code openapi.yaml})의
 * {@code POST /api/chat/rooms/&#123;roomId&#125;/messages}. 이슈 #79.
 *
 * <p><b>검증을 여기 두지 않는다.</b> 본문이 비었는지·컬럼 폭을 넘는지는 전부
 * {@code ChatRoomService} 안이고({@code validBody}·{@code validContentType}·
 * {@code validClientMsgId}), 이 레코드는 JSON 을 자바로 옮기는 자리다. 검증이 두 곳에 살면
 * 한쪽만 낡는다 — 그때 실제로 나가는 답은 400 이 아니라 <b>500</b> 이다(#78 에서 실측했다).
 *
 * <p>{@code senderUserId}·{@code senderName} 이 없는 것은 의도다. 보낸 사람은 토큰이
 * 정하고, 클라이언트가 보낸 이름을 그대로 저장하면 아무나 남의 이름으로 말할 수 있다.
 *
 * @param clientMsgId 재전송 멱등키. 없으면 멱등을 요구하지 않는 전송이다 — 같은 본문이라도
 *                    두 줄이 된다({@code UNIQUE} 는 {@code NULL} 을 겹침으로 보지 않는다)
 * @param contentType 생략하면 {@code text}
 */
public record ChatSendRequest(String body, String clientMsgId, String contentType) {
}

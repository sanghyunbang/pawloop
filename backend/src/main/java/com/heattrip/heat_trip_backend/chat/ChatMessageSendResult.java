package com.heattrip.heat_trip_backend.chat;

/**
 * 전송의 결과 — 메시지와 <b>그것이 이번에 만들어졌는가</b>. 이슈 #79.
 *
 * <p>{@link #created} 가 있는 이유는 상태 코드 하나다. 처음 들어온 전송은 201 이고,
 * 같은 {@code clientMsgId} 로 다시 온 재전송은 <b>200</b> 이다 — 409 가 아니다. 재시도한
 * 클라이언트 입장에서 그 요청은 성공했고, 실제로 그 사람의 말은 방에 들어가 있다.
 * 409 를 주면 앱은 "실패" 화면을 띄우면서 정작 메시지는 보이는 상태가 된다.
 *
 * <p>본문은 두 경우가 <b>같다</b>. 재전송에는 처음 배정된 {@code roomSeq} 가 그대로 실린다
 * (완료 조건 3) — 그래야 앱이 같은 말풍선을 두 개 그리지 않는다.
 *
 * @param created {@code true} 면 이번 요청이 만든 메시지(201), {@code false} 면 이미 있던
 *                메시지를 그대로 돌려준 것(200)
 */
public record ChatMessageSendResult(ChatMessageView message, boolean created) {
}

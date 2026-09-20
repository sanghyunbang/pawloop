/**
 * 푸시 알림 — 기기 토큰 원장, 사용자별 알림 설정, 채팅 메시지의 커밋 뒤 비동기 발송 (이슈 #83).
 *
 * <h2>이 모듈이 아는 것 · 모르는 것</h2>
 * <p>아는 것은 "누구의 어느 기기에 어떤 토큰이 살아 있는가" 와 "그 사람이 알림을 껐는가" 다.
 * <b>방별 음소거는 모른다</b> — 그건 멤버십의 속성이라 {@code chat_room_member.muted_at} 에 있고,
 * {@code ChatRoomService.notifiableMembers} 가 답한다. 이 모듈은 그 답에 전역 설정과 토큰을 얹을 뿐이다.
 *
 * <h2>발송은 커밋 뒤, 다른 스레드에서</h2>
 * <p>{@code chat} 이 메시지를 저장하면서 {@code ChatMessagePosted} 를 발행하고, 여기의
 * {@code PushDispatcher} 가 {@code AFTER_COMMIT} + {@code @Async} 로 받는다. 메시지 저장 트랜잭션 안에서
 * 외부 HTTP 를 부르면 FCM 지연이 곧 채팅 지연이고, 방 행 잠금을 쥔 채 기다리게 된다(#83 완료 조건 3).
 *
 * <h2>키가 없어도 뜬다</h2>
 * <p>Firebase 서비스 계정 키({@code app.push.firebase.*})가 없으면 {@code NoopFcmClient} 가 대신 들어가
 * 등록·설정·음소거는 저장되고 발송만 조용히 건너뛴다 — #301 의 Apple 키와 같은 방식이다.
 *
 * <h2>의존 방향</h2>
 * <p>{@code push -> chat}(이벤트 · 수신자 질의) · {@code push -> user}(세션 종료 이벤트 · {@code @CurrentUser} ·
 * {@code User}) · {@code push -> schedule}(배정 이벤트 {@code ScheduleAssigned}, #735). {@code chat} · {@code user} ·
 * {@code schedule} 은 이 모듈을 모른다.
 */
@ApplicationModule(
        displayName = "Push",
        allowedDependencies = { "chat", "user", "user :: entity", "schedule" })
package com.heattrip.heat_trip_backend.push;

import org.springframework.modulith.ApplicationModule;

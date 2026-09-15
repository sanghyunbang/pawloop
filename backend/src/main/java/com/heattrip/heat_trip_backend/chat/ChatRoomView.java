package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 방 하나를 chat 밖으로 내보내는 모양 — 이슈 #75.
 *
 * <h2>왜 엔티티를 그대로 주지 않는가</h2>
 * <p>{@code ChatRoom} 엔티티를 돌려주면 밖의 코드가 {@code chat.entity} 를 이름으로 알게 되고,
 * 그 순간 "방을 어떻게 저장하는가" 가 남의 모듈의 컴파일 의존이 된다. 지연 로딩된 연관을
 * 트랜잭션 밖에서 건드리는 사고도 같은 문에서 들어온다.
 *
 * <p>그래서 밖으로 나가는 것은 <b>값</b>뿐이다. 이 규칙을 {@code ChatBoundaryArchitectureTest}
 * 의 §E 가 잠근다 — chat 밖의 소스는 {@code chat.entity}·{@code chat.repository} 를 이름으로
 * 부를 수 없다.
 *
 * @param originKind 방을 만든 도메인 이름. 불투명 문자열이다 — chat 은 이 값을 해석하지 않는다
 * @param originRef  그 도메인의 id 를 문자열로. <b>FK 가 아니다</b>
 */
public record ChatRoomView(
        long id,
        String originKind,
        String originRef,
        String name,
        String tag,
        long lastSeq,
        long lastChangeSeq,
        LocalDateTime createdAt) {
}

package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

/**
 * 방 조회. 출처 쌍으로 찾는 것이 유일한 진입점이다 — 이슈 #74.
 *
 * <p>{@code findByOriginKindAndOriginRef} 는 조회일 뿐 <b>확인-후-쓰기의 근거가 아니다.</b>
 * "없으면 만든다" 를 이 조회로 판정하면 두 요청이 동시에 통과한다. 중복을 막는 것은
 * {@code UNIQUE (origin_kind, origin_ref)} 이고, 진 쪽은 예외를 받는다(ADR-0011 · 원칙 5).
 */
public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {

    Optional<ChatRoom> findByOriginKindAndOriginRef(String originKind, String originRef);
}

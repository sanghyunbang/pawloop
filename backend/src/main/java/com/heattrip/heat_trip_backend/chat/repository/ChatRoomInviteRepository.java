package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

/**
 * 초대코드 조회 — 이슈 #74.
 *
 * <p>{@code findByCode} 가 유일한 조회 경로다. UNIQUE 라 "코드 1개 = 행 1개" 이고,
 * 그게 깨지면 어느 행을 줄지 미정이 된다({@code refresh_token.token_hash} 와 같은 계열).
 */
public interface ChatRoomInviteRepository extends JpaRepository<ChatRoomInvite, Long> {

    Optional<ChatRoomInvite> findByCode(String code);
}

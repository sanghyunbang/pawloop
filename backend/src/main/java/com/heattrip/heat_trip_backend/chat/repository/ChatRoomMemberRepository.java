package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * 방 멤버십 조회 — 이슈 #74.
 *
 * <p>메서드가 {@code Long roomId} 를 받지 {@code User} 를 받지 않는다. chat 은 사용자를
 * 값으로만 안다({@code ChatRoomMember} javadoc 참조).
 */
public interface ChatRoomMemberRepository extends JpaRepository<ChatRoomMember, Long> {

    Optional<ChatRoomMember> findByRoomIdAndUserId(Long roomId, Long userId);

    /** 방의 살아 있는 멤버. 강퇴된 행({@code removed_at} 이 찍힌 행)은 뺀다. */
    List<ChatRoomMember> findByRoomIdAndRemovedAtIsNull(Long roomId);

    /** 정원 검사의 좌변. 강퇴된 행은 정원을 차지하지 않는다. */
    long countByRoomIdAndRemovedAtIsNull(Long roomId);
}

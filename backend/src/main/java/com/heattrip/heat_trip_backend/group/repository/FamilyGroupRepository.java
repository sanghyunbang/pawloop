package com.heattrip.heat_trip_backend.group.repository;

import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 가족 그룹 조회 — 이슈 #75.
 *
 * <p><b>"내 그룹" 을 찾는 메서드가 여기 없다.</b> 멤버십은 {@code chat_room_member} 에 살고
 * (ADR-0011 결정 1) 이 표에는 사용자 컬럼이 없다. 내가 속한 그룹은 chat 에게 "내가 멤버인
 * {@code FAMILY} 방들" 을 물어 {@code origin_ref} 로 되찾는다 — {@code FamilyGroupService} 참조.
 * 여기에 사용자로 찾는 메서드를 만들려면 멤버십 표가 하나 더 있어야 하고, 그건 만들지 않는다.
 */
public interface FamilyGroupRepository extends JpaRepository<FamilyGroup, Long> {
}

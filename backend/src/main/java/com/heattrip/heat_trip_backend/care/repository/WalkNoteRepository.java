package com.heattrip.heat_trip_backend.care.repository;

import com.heattrip.heat_trip_backend.care.entity.WalkNote;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

/**
 * 산책 주의사항 조회 — 이슈 #76. 그룹당 한 장이라 {@link Optional} 하나다.
 */
public interface WalkNoteRepository extends JpaRepository<WalkNote, Long> {

    /**
     * 이 그룹의 메모. 아직 아무도 안 썼으면 비어 있다.
     *
     * <p>{@code join fetch n.updatedBy} 는 응답의 "마지막으로 고친 사람" 때문이다.
     * 없으면 조회 한 번에 {@code users} 왕복이 하나 더 붙는다.
     *
     * <p>여기도 {@code n.group.id = :groupId} 가 <b>필터</b>다 — 인가와 별개의 방어라는
     * 것은 {@code CareLogRepository.findDayOfGroup} 의 javadoc 과 같다.
     */
    @Query("""
            select n from WalkNote n
              join fetch n.updatedBy
             where n.group.id = :groupId
            """)
    Optional<WalkNote> findByGroupId(@Param("groupId") long groupId);
}

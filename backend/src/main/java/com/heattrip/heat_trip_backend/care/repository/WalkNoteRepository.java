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
     * <p>{@code left join fetch n.updatedBy} 는 응답의 "마지막으로 고친 사람" 때문이다.
     * 없으면 조회 한 번에 {@code users} 왕복이 하나 더 붙는다.
     *
     * <p><b>{@code left} 여야 한다 — 실측으로 확인한 자리다.</b> {@code updated_by} 를
     * {@code ON DELETE SET NULL} 로 내린 뒤에도 이 줄이 inner 인 동안은 <b>아무것도 고쳐지지
     * 않았다</b>: 행은 DB 에 그대로 남는데 이 쿼리가 그것을 못 찾고, 서비스는
     * {@code orElseGet(WalkNoteResponse::empty)} 로 <b>빈 본문</b>을 답했다. 화면에서는
     * 행이 지워지던 옛 CASCADE 동작과 글자 하나 다르지 않다
     * ({@code CareSharingIntegrationTest.whenOneMemberWithdraws_...} 가 FK 만 고친 상태에서
     * {@code expected: "오른쪽 뒷다리 슬개골 — 계단 피하기" but was: ""} 로 여전히 빨간불이었다).
     *
     * <p>여기도 {@code n.group.id = :groupId} 가 <b>필터</b>다 — 인가와 별개의 방어라는
     * 것은 {@code CareLogRepository.findDayOfGroup} 의 javadoc 과 같다.
     */
    @Query("""
            select n from WalkNote n
              left join fetch n.updatedBy
             where n.group.id = :groupId
            """)
    Optional<WalkNote> findByGroupId(@Param("groupId") long groupId);
}

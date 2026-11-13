package com.heattrip.heat_trip_backend.moderation.repository;

import com.heattrip.heat_trip_backend.moderation.entity.ModerationAction;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

/** 운영자 조치 이력 — 이슈 #718. */
public interface ModerationActionRepository extends JpaRepository<ModerationAction, Long> {

    /** 이 신고에 내린 판단(지움·기각) — 오래된 것부터. 한 신고에 판단은 한 번이라 보통 0~2줄(대상이 둘이면 둘). */
    @Query("""
            select a from ModerationAction a
             where a.report.id = :reportId and a.kind in ('remove', 'dismiss')
             order by a.id
            """)
    List<ModerationAction> findDecisionsOf(@Param("reportId") long reportId);

    /**
     * 이 사람의 마지막 정지·해제 한 줄 — 정지 판정의 뜨거운 길이다(로그인한 요청마다 한 번).
     * {@code idx_moderation_action_subject (subject_user_id, id)} 를 거꾸로 훑어 첫 줄에서 멈춘다.
     */
    Optional<ModerationAction> findFirstBySubjectUserIdAndKindInOrderByIdDesc(Long subjectUserId,
                                                                             Collection<String> kinds);

    /** 이 사람이 받은 조치 — 최근 것부터 스무 줄. 운영자가 정지·해제를 판단할 때 본다. */
    List<ModerationAction> findTop20BySubjectUserIdOrderByIdDesc(Long subjectUserId);
}

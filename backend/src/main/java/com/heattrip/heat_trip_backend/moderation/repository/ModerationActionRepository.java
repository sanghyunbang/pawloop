package com.heattrip.heat_trip_backend.moderation.repository;

import com.heattrip.heat_trip_backend.moderation.entity.ModerationAction;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

/** 운영자 조치 이력 — 이슈 #718. */
public interface ModerationActionRepository extends JpaRepository<ModerationAction, Long> {

    /** 이 신고에 내린 판단(지움·기각) — 오래된 것부터. 한 신고에 판단은 한 번이라 보통 0~2줄(대상이 둘이면 둘). */
    @Query("""
            select a from ModerationAction a
             where a.report.id = :reportId and a.kind in ('remove', 'dismiss')
             order by a.id
            """)
    List<ModerationAction> findDecisionsOf(@Param("reportId") long reportId);
}

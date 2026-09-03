package com.heattrip.heat_trip_backend.moderation.repository;

import com.heattrip.heat_trip_backend.moderation.entity.ReportSnapshot;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/**
 * 신고 시점 사본 — 이슈 #166.
 *
 * <p>부모({@code report})가 사라지면 함께 사라진다. 여기서 지우는 경로를 따로 두지 않는
 * 이유가 그것이다.
 */
public interface ReportSnapshotRepository extends JpaRepository<ReportSnapshot, Long> {

    /** 한 신고의 사본들. 대상이 먼저 오도록 {@code role} 로 정렬한다 — {@code context} 보다 앞이다. */
    List<ReportSnapshot> findByReportIdOrderByRoleAscIdAsc(long reportId);
}

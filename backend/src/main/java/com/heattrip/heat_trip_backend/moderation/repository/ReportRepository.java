package com.heattrip.heat_trip_backend.moderation.repository;

import com.heattrip.heat_trip_backend.moderation.entity.Report;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 신고 저장 — 이슈 #166.
 *
 * <p>지금은 쓰기와 목록뿐이다. 조회 축이 더 필요해지는 것은 운영 화면이 생기는 날이고,
 * 그때 무엇으로 거를지는 실제로 쌓인 신고를 보고 정하는 편이 낫다.
 */
public interface ReportRepository extends JpaRepository<Report, Long> {
}

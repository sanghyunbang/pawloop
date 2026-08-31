package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatReport;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/**
 * 신고 저장소 — 이슈 #82.
 *
 * <p>{@code chat_report} 는 {@code chat} 경계 <b>안</b>이고 {@code reporter_user_id} ·
 * {@code reported_user_id} 는 불투명한 값이다. 여기서 {@code users} 를 조인하지 않는다
 * ({@code ChatBoundaryArchitectureTest} 가 잠근다).
 */
public interface ChatReportRepository extends JpaRepository<ChatReport, Long> {

    /** 이 사람이 받은 신고. 운영자가 "몇 번 받았나" 를 물을 때 쓴다. */
    List<ChatReport> findByReportedUserIdOrderByIdDesc(Long reportedUserId);

    /** 이 사람이 낸 신고. 중복 신고를 볼 때 쓴다. */
    List<ChatReport> findByReporterUserIdOrderByIdDesc(Long reporterUserId);
}

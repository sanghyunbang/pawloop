// src/main/java/com/heattrip/heat_trip_backend/tour/schedules/TourFetchScheduler.java
package com.heattrip.heat_trip_backend.tour.schedules;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.heattrip.heat_trip_backend.tour.service.PlaceImportService;
import com.heattrip.heat_trip_backend.tour.service.TraitSnapshotService;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;

/**
 * - 매일 02:10: places 전체 수집 → 스냅샷 전량 재빌드.
 * - 외부 API는 JSON으로 받고, 수집은 PlaceImportService가 담당(기존 코드 유지).
 * - 스냅샷은 조인 결과를 물리 테이블로 저장(FK 없음).
 */
@Component
@RequiredArgsConstructor
public class TourFetchScheduler {
    private final PlaceImportService importer;        // 이미 존재
    private final TraitSnapshotService snapshotSvc;   // 새로 추가된 스냅샷 서비스

    // 앱 시작 시 즉시 1회 실행이 필요하면 @PostConstruct 복원
    // @PostConstruct
    // public void runOnStartUp() throws Exception {
    //     importer.fullImportAllAreas();
    //     snapshotSvc.rebuildAllSnapshots(1000);
    // }

    /** 매일 02:10 실행 (Asia/Seoul) */
    // @Scheduled(cron = "0 10 2 * * *", zone = "Asia/Seoul")
    // public void runDaily() throws Exception {
    //     importer.fullImportAllAreas();          // 1) places 최신화 (외부 API → JSON)
    //     snapshotSvc.rebuildAllSnapshots(1000);  // 2) 스냅샷 전량 재빌드
    // }
}

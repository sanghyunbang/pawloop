package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.entity.TrailRoute;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

/** 산책로 선 — 이슈 #291. */
public interface TrailRouteRepository extends JpaRepository<TrailRoute, String> {

    /**
     * 이 시각 이후에 받은 코스의 id. 적재가 <b>이미 신선한 코스의 GPX 를 다시 받지 않게</b> 한다 —
     * GPX 는 예산에 안 잡히지만 2,000 파일이고, 두루누비 서버에 예의가 아니다.
     */
    @Query("select r.courseId from TrailRoute r where r.fetchedAt >= :since")
    List<String> courseIdsFetchedSince(@Param("since") LocalDateTime since);
}

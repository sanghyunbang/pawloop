package com.heattrip.heat_trip_backend.push.repository;

import com.heattrip.heat_trip_backend.push.entity.PushPreference;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface PushPreferenceRepository extends JpaRepository<PushPreference, Long> {

    /** 알림을 <b>끈</b> 사람들 — 행이 없는 사람은 켜진 것이라, 끈 쪽만 물어보면 된다. */
    @Query("select p.userId from PushPreference p where p.userId in :userIds and p.enabled = false")
    List<Long> disabledAmong(@Param("userIds") Collection<Long> userIds);
}

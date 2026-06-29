package com.heattrip.heat_trip_backend.schedules.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import com.heattrip.heat_trip_backend.schedules.entity.*;
import com.heattrip.heat_trip_backend.user.entity.*;

public interface ScheduleRepository extends JpaRepository<Schedule, Integer>{
    List<Schedule> findByUser(User user);

}
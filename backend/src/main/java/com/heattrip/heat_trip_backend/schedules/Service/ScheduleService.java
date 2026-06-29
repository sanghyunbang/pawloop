package com.heattrip.heat_trip_backend.schedules.Service;

import org.springframework.stereotype.Service;

import com.heattrip.heat_trip_backend.schedules.entity.Schedule;
import com.heattrip.heat_trip_backend.schedules.repository.JourneyRepository;
import com.heattrip.heat_trip_backend.schedules.repository.JourneyRepository_v2;
import com.heattrip.heat_trip_backend.schedules.repository.ScheduleRepository;
import com.heattrip.heat_trip_backend.user.entity.*;
import com.heattrip.heat_trip_backend.user.repository.*;
import java.util.List;

@Service
public class ScheduleService {
    private final ScheduleRepository schedulerepository;
    private final UserRepository repository;
    private final JourneyRepository_v2 journeyRepo;

    public ScheduleService(ScheduleRepository schedulerepository, UserRepository repository, JourneyRepository_v2 journeyRepo){
        this.schedulerepository = schedulerepository;
        this.repository = repository;
        this.journeyRepo = journeyRepo;
    }

    public List<Schedule> findAll() {
        return schedulerepository.findAll();
    }
    public Schedule save(Schedule schedule) {
    return schedulerepository.save(schedule);
    }
    public List<User> userinfo(){
        return repository.findAll();
    }
    public List<Schedule> findByUser(User user) {
    return schedulerepository.findByUser(user);
    }
    public Schedule findById(Integer id) {
        return schedulerepository.findById(id).orElse(null);
    }
    public void delete(Schedule schedule) {
    schedulerepository.delete(schedule);
    }
    public int countJourneysBySchedule(Integer scheduleId) {
    return journeyRepo.countBySchedule_ScheduleId(scheduleId);
}



}

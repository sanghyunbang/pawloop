package com.heattrip.heat_trip_backend.schedules.Service;

import java.util.List;

import org.springframework.stereotype.Service;

import com.heattrip.heat_trip_backend.schedules.DTO.JourneyRequestDto;
import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.schedules.entity.Schedule;
import com.heattrip.heat_trip_backend.schedules.repository.JourneyRepository;
import com.heattrip.heat_trip_backend.schedules.repository.ScheduleRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

@Service
public class JourneyService {
    private final JourneyRepository journeyRepo;
    private final UserRepository userRepo;
    private final ScheduleRepository scheduleRepo;

    public JourneyService(JourneyRepository journeyRepo, UserRepository userRepo, ScheduleRepository scheduleRepo) {
        this.journeyRepo = journeyRepo;
        this.userRepo = userRepo;
        this.scheduleRepo = scheduleRepo;
    }

    public List<Journey> getJourneysByUser(User user) {
        return journeyRepo.findByUser(user);
    }

    public Journey saveJourney(JourneyRequestDto dto, User user) {
        Schedule schedule = null;
        if (dto.getScheduleId() != null) {
            schedule = scheduleRepo.findById(dto.getScheduleId()).orElse(null);
        }

        Journey journey = Journey.builder()
            .user(user)
            .schedule(schedule)
            .title(dto.getTitle())
            .date(dto.getDate())
            .location(dto.getLocation())
            .weatherLabel(dto.getWeatherLabel())
            .moodLabel(dto.getMoodLabel())
            .body(dto.getBody())
            .photos(dto.getPhotos())
            .build();

        return journeyRepo.save(journey);
    }
}


package com.heattrip.heat_trip_backend.schedules.DTO;

import java.time.LocalDate;
import java.util.List;

import com.heattrip.heat_trip_backend.schedules.entity.Journey;

import lombok.Data;

@Data
public class JourneyResponseDto {
    private Integer id;
    private String title;
    private LocalDate date;
    private String location;
    private String weatherLabel;
    private String moodLabel;
    private String body;
    private List<String> photos;
    private String userNickname;

    private Integer scheduleId;
    private Long placeId;

    public JourneyResponseDto(Journey journey) {
        this.id = journey.getId();
        this.title = journey.getTitle();
        this.date = journey.getDate();
        this.location = journey.getLocation();
        this.weatherLabel = journey.getWeatherLabel();
        this.moodLabel = journey.getMoodLabel();
        this.body = journey.getBody();
        this.placeId = journey.getPlaceId();
        this.photos = journey.getPhotos();
        this.userNickname = journey.getUser().getNickname();

        // schedule이 존재하면 id를 가져오고, 없으면 null 처리
        this.scheduleId = journey.getSchedule() != null ? journey.getSchedule().getScheduleId() : null;
    }
}

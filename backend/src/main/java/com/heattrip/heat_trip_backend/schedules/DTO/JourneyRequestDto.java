package com.heattrip.heat_trip_backend.schedules.DTO;

import java.time.LocalDate;
import java.util.List;

import lombok.Data;

@Data
public class JourneyRequestDto {
    private Integer scheduleId;
    private String title;
    private LocalDate date;
    private String location;
    private String weatherLabel;
    private String moodLabel;
    private String body;
    private List<String> photos;
    /** 추천 장소에서 기록한 경우의 장소 contentid. 구버전 클라이언트는 생략(null). */
    private Long placeId;
}


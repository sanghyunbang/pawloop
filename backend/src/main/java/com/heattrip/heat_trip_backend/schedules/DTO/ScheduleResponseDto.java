package com.heattrip.heat_trip_backend.schedules.DTO;

import java.time.LocalDate;
import java.time.LocalDateTime;

import com.heattrip.heat_trip_backend.schedules.entity.Schedule;

import lombok.Data;

@Data
public class ScheduleResponseDto {
    private Integer scheduleId;
    private String title;
    private String content;
    private LocalDate dateFrom;
    private LocalDate dateTo;
    private String userNickname;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    private int journeyCount; //scheduleId 값을 가지는 journey 갯수

    public ScheduleResponseDto(Schedule schedule) {
        this.scheduleId = schedule.getScheduleId();
        this.title = schedule.getTitle();
        this.content = schedule.getContent();
        this.dateFrom = schedule.getDateFrom();
        this.dateTo = schedule.getDateTo();
        this.userNickname = schedule.getUser().getNickname();
        this.createdAt = schedule.getCreatedAt();
        this.updatedAt = schedule.getUpdatedAt();
    }

    public ScheduleResponseDto(Schedule schedule, int journeyCount) {
        this(schedule); // 기존 생성자 호출
        this.journeyCount = journeyCount;
    }
}

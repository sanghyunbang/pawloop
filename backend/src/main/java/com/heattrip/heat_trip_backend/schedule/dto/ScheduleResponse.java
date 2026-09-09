package com.heattrip.heat_trip_backend.schedule.dto;

import com.heattrip.heat_trip_backend.schedule.ScheduleTime;
import com.heattrip.heat_trip_backend.schedule.entity.Schedule;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleStatus;
import com.heattrip.heat_trip_backend.user.entity.User;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 계약의 {@code Schedule} — 이슈 #418.
 *
 * @param version   고칠 때 그대로 되돌려 보내야 하는 값. 다르면 409 다
 * @param atTime    {@code null} 이면 <b>"하루 종일"</b> 이다. 화면이 그 묶음으로 그린다
 * @param assignee  맡은 사람. id 가 아니라 {@link Person} 인 이유는 화면이 "아빠 담당" 을
 *                  그리려면 이름이 필요하고, id 만 주면 목록마다 한 번 더 물어야 해서다
 * @param updatedBy 마지막으로 고친 사람. 화면의 "○○님이 방금 고쳤어요" 가 이 값이다
 * @param doneAt    <b>오프셋이 붙는다</b> — 서버가 찍는 순간이라 UTC 다. 반대로
 *                  {@code onDate}·{@code atTime} 은 사람이 고른 벽시계라 변환하지 않는다
 *                  ({@link ScheduleTime})
 */
public record ScheduleResponse(
        Long id,
        ScheduleOwnerKind ownerKind,
        Long ownerRef,
        Long dogId,
        ScheduleKind kind,
        String title,
        String memo,
        LocalDate onDate,
        LocalTime atTime,
        Person assignee,
        ScheduleStatus status,
        Instant doneAt,
        Integer version,
        Person updatedBy,
        Instant updatedAt) {

    /** 사람 한 명 — id 와 이름. 없거나 탈퇴했으면 이 객체 자체가 {@code null} 이다. */
    public record Person(Long userId, String nickname) {
    }

    public static ScheduleResponse of(Schedule s) {
        return new ScheduleResponse(
                s.getId(),
                s.getOwnerKind(),
                s.getOwnerRef(),
                s.getDog() == null ? null : s.getDog().getId(),
                s.getKind(),
                s.getTitle(),
                s.getMemo(),
                s.getOnDate(),
                s.getAtTime(),
                person(s.getAssignee()),
                s.getStatus(),
                ScheduleTime.toInstant(s.getDoneAt()),
                s.getVersion(),
                person(s.getUpdatedBy()),
                ScheduleTime.toInstant(s.getUpdatedAt()));
    }

    private static Person person(User user) {
        return user == null ? null : new Person(user.getId(), user.getNickname());
    }
}

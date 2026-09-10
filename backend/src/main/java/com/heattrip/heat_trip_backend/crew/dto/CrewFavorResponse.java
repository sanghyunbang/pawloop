package com.heattrip.heat_trip_backend.crew.dto;

import com.heattrip.heat_trip_backend.crew.CrewTime;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavor;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavorSlot;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavorStatus;
import com.heattrip.heat_trip_backend.user.entity.User;

import java.time.Instant;
import java.time.LocalDate;

/**
 * 계약의 {@code CrewFavor} — 이슈 #417.
 *
 * @param mine       내가 올린 부탁인가. <b>지우기 버튼을 그릴지</b> 정한다
 * @param takenByMe  내가 맡은 것인가. "제가 할게요" 와 "무르기" 를 가른다
 * @param scheduleId 맡으면 생기는 크루 일정. 화면이 달력의 그 줄로 갈 수 있게 함께 준다.
 *                   안 맡았으면 {@code null}
 */
public record CrewFavorResponse(
        Long id,
        LocalDate onDate,
        CrewFavorSlot slot,
        String note,
        CrewFavorStatus status,
        Person askedBy,
        Person takenBy,
        Pet dog,
        boolean mine,
        boolean takenByMe,
        Long scheduleId,
        Instant createdAt) {

    /** 사람 한 명 — id 와 이름. 탈퇴했으면 이름이 {@code 알 수 없음} 이다. */
    public record Person(Long userId, String nickname) {
        static Person of(User user) {
            return user == null ? null : new Person(user.getId(), user.displayName());
        }
    }

    /**
     * 아이 하나 — id 와 이름.
     *
     * <p>품종·나이를 안 싣는다. 카드가 말해야 하는 것은 "누구를 맡기나" 이고, 그 이상은
     * 남의 아이 정보를 크루 전체에 흘리는 것이다.
     */
    public record Pet(Long dogId, String name) {
    }

    public static CrewFavorResponse of(CrewFavor favor, long viewerId) {
        Long askerId = favor.getAskedBy() == null ? null : favor.getAskedBy().getId();
        Long takerId = favor.getTakenBy() == null ? null : favor.getTakenBy().getId();

        return new CrewFavorResponse(
                favor.getId(),
                favor.getOnDate(),
                favor.getSlot(),
                favor.getNote(),
                favor.getStatus(),
                Person.of(favor.getAskedBy()),
                Person.of(favor.getTakenBy()),
                favor.getDog() == null
                        ? null
                        : new Pet(favor.getDog().getId(), favor.getDog().getName()),
                askerId != null && askerId == viewerId,
                takerId != null && takerId == viewerId,
                favor.getScheduleId(),
                CrewTime.toInstant(favor.getCreatedAt()));
    }
}

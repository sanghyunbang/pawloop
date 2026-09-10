package com.heattrip.heat_trip_backend.schedule;

import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.schedule.service.ScheduleService;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * "크루가 정한 일을 달력에 한 줄로 남긴다" — <b>{@code schedule} 모듈의 공개 표면이다.</b>
 * 이슈 #417(품앗이), 부모 #416.
 *
 * <h2>왜 이 타입이 있어야 하는가</h2>
 * <p>품앗이는 <b>약속</b>이다. "12/24 오후, 보리 두 시간만 봐 주실 분" 을 누군가 맡으면 그
 * 약속은 <b>그날 아침에 보여야</b> 한다. 크루 화면에만 두면 그날 아침에 아무도 그것을 안
 * 본다 — 사람은 아침에 달력을 보지 크루 목록을 보지 않는다.
 *
 * <p>그렇다고 {@code crew} 가 {@code schedule.service.ScheduleService} 를 직접 부르면 안
 * 된다({@code backend-implementation-guide.md} §2.3). {@code care} 가
 * {@link com.heattrip.heat_trip_backend.care.CareLogging} 을 내준 것과 같은 자리다.
 *
 * <h2>반대 방향은 없다 — 고리를 안 만든다</h2>
 * <p>{@code schedule} 은 크루 일정의 권한을 잴 때 {@code crew} 를 <b>안 부른다.</b>
 * 재는 것이 "그 방의 살아 있는 멤버인가" 하나라 {@code chat} 만 알면 되고, 출처 이름은
 * {@code ScheduleOwnerKind.CREW_ORIGIN_KIND} 가 직접 든다. 부르면 {@code crew ↔ schedule}
 * 고리가 되고 {@code ModuleCycleTest} 가 잡는다.
 *
 * <h2>아이는 <b>행</b>으로 받는다</h2>
 * <p>{@code dogId} 를 받으면 이 모듈이 "그 아이가 누구 것인가" 를 다시 물어야 하는데, 품앗이의
 * 아이는 <b>맡은 사람이 아니라 부탁한 사람의</b> 것이다. 소유권은 부탁을 올릴 때 이미
 * 확인했으므로({@code DogOwnership.requireMineEntity}), 여기서는 그 행을 그대로 받는다 —
 * {@code Schedule} 이 {@code @ManyToOne Dog} 를 들어야 {@code fk_schedule_dog} 가 선다.
 */
@Component
public class CrewSchedules {

    private final ScheduleService schedules;

    public CrewSchedules(ScheduleService schedules) {
        this.schedules = schedules;
    }

    /**
     * 크루 소유 일정 한 줄을 남긴다.
     *
     * <p>{@code owner_kind=room}, {@code owner_ref=crewId} 라 <b>그 크루 사람 모두의 달력</b>에
     * 뜬다. 맡은 사람이 담당자다 — 누가 하기로 했는지가 그 줄의 알맹이다.
     *
     * <p>시각을 안 받는다. 품앗이가 정하는 것은 <b>시간대</b>(오전·오후·저녁)이지 시각이
     * 아니고, 0시로 채우면 달력이 그것을 "새벽 12시" 로 그린다. 시간대는 메모로 간다.
     *
     * @param crewId   {@code crew.id}. 방 id 가 아니다
     * @param assignee 맡은 사람. 그 크루의 멤버여야 하고, 아니면 404 다
     * @param dog      부탁한 사람의 아이. 없으면 {@code null}
     * @return 만들어진 일정의 id. 부르는 쪽이 그것을 들고 있다가 무를 때 거둔다
     */
    public long line(long crewId, LocalDate onDate, String title, String memo,
                     Dog dog, User assignee) {
        return schedules.createCrewLine(crewId, onDate, title, memo, dog, assignee);
    }

    /**
     * 그 줄을 거둔다. <b>없으면 아무 일도 안 한다.</b>
     *
     * <p>품앗이를 무르면 달력의 줄도 사라져야 한다 — 안 그러면 아무도 안 하기로 한 일이
     * 그날 아침에 뜬다.
     */
    public void remove(Long scheduleId) {
        schedules.removeCrewLine(scheduleId);
    }
}

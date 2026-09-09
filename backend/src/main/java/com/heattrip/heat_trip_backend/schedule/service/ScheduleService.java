package com.heattrip.heat_trip_backend.schedule.service;

import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.group.service.FamilyGroupService;
import com.heattrip.heat_trip_backend.schedule.ScheduleTime;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleRequest;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleResponse;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleUpdateRequest;
import com.heattrip.heat_trip_backend.schedule.entity.Schedule;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleStatus;
import com.heattrip.heat_trip_backend.schedule.repository.ScheduleRepository;
import com.heattrip.heat_trip_backend.user.KnownUsers;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * 일정표 — 이슈 #418, 부모 #416.
 *
 * <h2>거절은 전부 404 다</h2>
 * <p>남의 아이 일정도, 안 든 그룹의 일정도, 없는 id 도 <b>같은 404</b> 다. 403 을 주면
 * "그 id 는 있다" 를 알려 주게 되고, 그러면 id 를 훑어 남의 가족 구성을 짐작할 수 있다.
 * {@code WalkService} 가 산책 상세에서 고른 답과 같다.
 *
 * <p>예외는 하나 — <b>낙관적 잠금 충돌은 409</b> 다. 그건 권한 문제가 아니라 "지금 값이
 * 달라졌다" 는 사실이고, 화면이 그것을 알아야 최신 값을 보여 줄 수 있다.
 *
 * <h2>멤버십의 원본은 {@code chat_room_member} 다</h2>
 * <p>{@code family_group} 을 보지 않는다(ADR-0011 결정 1). {@code CareService} 가 같은 자리에서
 * 같은 길을 쓴다 — {@link ChatRoomService#findRoom} 과 {@link ChatRoomService#isLiveMember}.
 *
 * <h2>기간에 상한이 있다</h2>
 * <p>달력은 한 달을 본다. 상한이 없으면 한 요청이 몇 년치를 끌어오고, 그건 느린 것이 아니라
 * <b>메모리를 먹는</b> 문제다. 92일이면 석 달치라 "이번 달 ± 한 달" 이 한 번에 들어온다.
 */
@Service
public class ScheduleService {

    /** 한 번에 볼 수 있는 최대 기간(일). 석 달치 — "이번 달 ± 한 달" 이 한 번에 들어온다. */
    public static final int MAX_RANGE_DAYS = 92;

    private final ScheduleRepository schedules;
    private final DogOwnership dogs;
    private final ChatRoomService chatRooms;
    private final KnownUsers users;
    private final Clock clock;

    public ScheduleService(ScheduleRepository schedules,
                           DogOwnership dogs,
                           ChatRoomService chatRooms,
                           KnownUsers users,
                           Clock clock) {
        this.schedules = schedules;
        this.dogs = dogs;
        this.chatRooms = chatRooms;
        this.users = users;
        this.clock = clock;
    }

    // ─────────────────────────── 쓰기 ───────────────────────────

    @Transactional
    public ScheduleResponse create(User me, ScheduleRequest request) {
        long userId = me.getId();
        requireOwner(userId, request.ownerKind(), request.ownerRef());

        Schedule saved = schedules.save(Schedule.builder()
                .ownerKind(request.ownerKind())
                .ownerRef(request.ownerRef())
                .dog(dogOrNull(userId, request.dogId()))
                .kind(request.kind())
                .title(request.title().strip())
                .memo(blankToNull(request.memo()))
                .onDate(request.onDate())
                .atTime(request.atTime())
                .assignee(assigneeOrNull(request.assignee(), request.ownerKind(), request.ownerRef()))
                .status(ScheduleStatus.PLANNED)
                .createdBy(me)
                .build());
        return ScheduleResponse.of(saved);
    }

    /**
     * 고친다. <b>안 보낸 필드는 안 바꾼다</b> — 화면이 한 칸만 고칠 수 있어야 한다.
     *
     * <p>{@code memo}·{@code atTime}·{@code dogId}·{@code assignee} 는 <b>비우는 것</b>과
     * "안 바꾸는 것" 을 구분하지 못한다(둘 다 {@code null} 로 온다). 지금은 <b>비우기</b>로
     * 본다 — 담당자를 뗄 길이 없는 것이 더 나쁘고, 화면이 늘 전체를 보내기 때문이다.
     * 계약에 그렇게 적었다.
     */
    @Transactional
    public ScheduleResponse update(User me, long scheduleId, int version,
                                   ScheduleUpdateRequest request) {
        long userId = me.getId();
        Schedule schedule = mine(userId, scheduleId);

        if (schedule.getVersion() != version) {
            throw new StaleScheduleException(ScheduleResponse.of(schedule));
        }

        schedule.edit(
                request.kind() == null ? schedule.getKind() : request.kind(),
                request.title() == null || request.title().isBlank()
                        ? schedule.getTitle() : request.title().strip(),
                blankToNull(request.memo()),
                request.onDate() == null ? schedule.getOnDate() : request.onDate(),
                request.atTime(),
                dogOrNull(userId, request.dogId()),
                assigneeOrNull(request.assignee(), schedule.getOwnerKind(), schedule.getOwnerRef()),
                me);

        if (request.status() != null && request.status() != schedule.getStatus()) {
            schedule.markStatus(request.status(), ScheduleTime.nowUtc(clock), me);
        }

        return ScheduleResponse.of(schedules.saveAndFlush(schedule));
    }

    @Transactional
    public void delete(long userId, long scheduleId) {
        schedules.delete(mine(userId, scheduleId));
    }

    // ─────────────────────────── 읽기 ───────────────────────────

    /**
     * 기간 안의 일정. <b>주인을 안 주면 "내가 볼 수 있는 전부"</b> 다 — 달력의 기본이 합쳐
     * 보기라, 그것을 화면이 N 번 부르게 만들지 않는다.
     */
    @Transactional(readOnly = true)
    public List<ScheduleResponse> range(long userId, LocalDate from, LocalDate to,
                                        ScheduleOwnerKind ownerKind, Long ownerRef, Long dogId) {
        validateRange(from, to);

        List<Schedule> found = new ArrayList<>();
        if (ownerKind == null) {
            found.addAll(ofDogs(userId, myDogIds(userId), from, to));
            found.addAll(ofGroups(myGroupIds(userId), from, to));
        } else {
            requireOwner(userId, ownerKind, ownerRef);
            found.addAll(ownerKind == ScheduleOwnerKind.DOG
                    ? ofDogs(userId, List.of(ownerRef), from, to)
                    : ofGroups(List.of(ownerRef), from, to));
        }

        return found.stream()
                .filter(s -> dogId == null
                        || (s.getDog() != null && dogId.equals(s.getDog().getId())))
                // 종류가 섞이면 순서가 두 목록의 이어 붙이기가 된다 — 날짜순으로 다시 세운다.
                .sorted(ScheduleService::byDateThenTime)
                .map(ScheduleResponse::of)
                .toList();
    }

    private static int byDateThenTime(Schedule a, Schedule b) {
        int date = a.getOnDate().compareTo(b.getOnDate());
        if (date != 0) {
            return date;
        }
        // 시각 없는 것("하루 종일")이 뒤다.
        if (a.getAtTime() == null || b.getAtTime() == null) {
            return a.getAtTime() == null ? (b.getAtTime() == null ? 0 : 1) : -1;
        }
        int time = a.getAtTime().compareTo(b.getAtTime());
        return time != 0 ? time : Long.compare(a.getId(), b.getId());
    }

    private List<Schedule> ofDogs(long userId, List<Long> dogIds, LocalDate from, LocalDate to) {
        List<Long> mine = dogIds.stream().filter(id -> isMyDog(userId, id)).toList();
        return mine.isEmpty()
                ? List.of()
                : schedules.findRange(ScheduleOwnerKind.DOG, mine, from, to);
    }

    private List<Schedule> ofGroups(List<Long> groupIds, LocalDate from, LocalDate to) {
        return groupIds.isEmpty()
                ? List.of()
                : schedules.findRange(ScheduleOwnerKind.GROUP, groupIds, from, to);
    }

    // ─────────────────────────── 권한 ───────────────────────────

    /**
     * 이 사람이 이 주인의 일정을 만들고 볼 수 있는가.
     *
     * <p>{@code room}(크루, #417)은 <b>아직 거절한다</b>. 값은 열려 있지만 그것을 확인할
     * 멤버십이 아직 없다 — 확인 없이 통과시키면 아무나 남의 크루 일정을 만들 수 있다.
     */
    private void requireOwner(long userId, ScheduleOwnerKind kind, Long ref) {
        if (kind == null || ref == null) {
            throw notFound();
        }
        switch (kind) {
            case DOG -> dogs.requireMine(userId, ref);
            case GROUP -> requireGroupMember(userId, ref);
            case ROOM -> throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "크루 일정은 아직 만들 수 없습니다.");
        }
    }

    private void requireGroupMember(long userId, long groupId) {
        ChatRoomView room = chatRooms
                .findRoom(FamilyGroupService.ORIGIN_KIND, String.valueOf(groupId))
                .orElseThrow(ScheduleService::notFound);
        if (!chatRooms.isLiveMember(room.id(), userId)) {
            throw notFound();
        }
    }

    /** 이 일정이 내 것인가. 아니거나 없으면 <b>같은 404</b> 다. */
    private Schedule mine(long userId, long scheduleId) {
        Schedule schedule = schedules.findById(scheduleId).orElseThrow(ScheduleService::notFound);
        requireOwner(userId, schedule.getOwnerKind(), schedule.getOwnerRef());
        return schedule;
    }

    private boolean isMyDog(long userId, Long dogId) {
        try {
            dogs.requireMine(userId, dogId);
            return true;
        } catch (RuntimeException notMine) {
            return false;
        }
    }

    private List<Long> myDogIds(long userId) {
        return dogs.myDogIds(userId);
    }

    /**
     * 내가 든 가족 그룹들.
     *
     * <p>지금 한 사람은 그룹 하나에만 든다({@code FamilyGroupService}). 그래도 목록으로
     * 받는 이유는 조회가 {@code IN} 이라 하나든 여럿이든 같은 모양이고, 여럿이 되는 날
     * 여기만 고치면 되기 때문이다.
     */
    private List<Long> myGroupIds(long userId) {
        return chatRooms.roomsOfMember(FamilyGroupService.ORIGIN_KIND, userId).stream()
                .map(ChatRoomView::originRef)
                .map(ScheduleService::toLongOrNull)
                .filter(java.util.Objects::nonNull)
                .toList();
    }

    private static Long toLongOrNull(String ref) {
        try {
            return Long.valueOf(ref);
        } catch (NumberFormatException notANumber) {
            // 출처 참조는 문자열이라(ADR-0011) 숫자가 아닌 값이 들어올 수 있다. 그건
            // 가족 그룹이 아니므로 조용히 건너뛴다.
            return null;
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private Dog dogOrNull(long userId, Long dogId) {
        return dogId == null ? null : dogs.requireMineEntity(userId, dogId);
    }

    /**
     * 담당자. <b>그 주인을 볼 수 있는 사람이어야 한다</b> — 아무나 담당으로 적으면 남의
     * 화면에 내가 모르는 일정이 뜨게 된다.
     */
    private User assigneeOrNull(Long assigneeId, ScheduleOwnerKind kind, Long ref) {
        if (assigneeId == null) {
            return null;
        }
        requireOwner(assigneeId, kind, ref);
        return users.byId(assigneeId).orElseThrow(ScheduleService::notFound);
    }

    private void validateRange(LocalDate from, LocalDate to) {
        if (from == null || to == null || to.isBefore(from)) {
            throw new IllegalArgumentException("조회 기간이 올바르지 않습니다.");
        }
        if (from.plusDays(MAX_RANGE_DAYS).isBefore(to)) {
            throw new IllegalArgumentException(
                    "한 번에 볼 수 있는 기간은 " + MAX_RANGE_DAYS + "일까지입니다.");
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }

    private static ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "일정을 찾을 수 없습니다.");
    }

    /**
     * 낙관적 잠금 충돌 — <b>409 와 함께 최신 값</b>을 준다.
     *
     * <p>본문 없는 409 를 주면 화면이 다시 물어야 하고, 그 사이에 또 바뀔 수 있다.
     * 최신 값을 함께 주면 "○○님이 방금 고쳤어요" 를 그 자리에서 보여 줄 수 있다.
     */
    public static class StaleScheduleException extends RuntimeException {
        private final transient ScheduleResponse current;

        public StaleScheduleException(ScheduleResponse current) {
            super("다른 사람이 먼저 고쳤습니다.");
            this.current = current;
        }

        public ScheduleResponse current() {
            return current;
        }
    }
}

package com.heattrip.heat_trip_backend.schedule.service;

import com.heattrip.heat_trip_backend.care.CareLogging;
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
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleRepeat;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleException;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleExceptionKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleStatus;
import com.heattrip.heat_trip_backend.schedule.repository.ScheduleExceptionRepository;
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
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
 * <h2>완료하면 케어 기록이 함께 남는다</h2>
 * <p>이슈 #420. 없으면 사람이 <b>같은 일을 두 곳에 두 번 적는다</b> — 일정에서 체크하고,
 * 오늘의 케어에서 병원 버튼을 또 누른다. 그러면 "오늘 병원 두 번" 이 기록에 남는다.
 *
 * <p>조건이 둘이다. <b>가족 소유</b>여야 하고({@code care_log} 가 그룹 축이다) 종류가
 * <b>케어여야 한다</b>({@link ScheduleKind#careWire}). 아이 소유 일정은 남기지 않는다 —
 * 넣을 그룹이 없다.
 *
 * <p>되돌리면 그 줄을 <b>거둔다</b>. 안 거두면 취소한 일이 오늘의 케어에 남고, 그건 이
 * 연결이 막으려던 "두 번 적기" 를 반대 방향으로 되살린다.
 *
 * <h2>반복은 규칙 한 줄이고, 조회가 펼친다</h2>
 * <p>이슈 #421. 1년치 심장사상충 약을 365행으로 만들어 두지 않는다 — 규칙을 고치면 그
 * 전부를 손봐야 하고, 그 손보기를 한 번 빠뜨리면 옛 값이 남은 행이 조용히 생긴다.
 *
 * <p>펼친 하루에는 <b>행이 없다</b>. 그 하루를 고치거나 완료하면 그때 비로소 행이 생기고
 * ({@link #overrideOneDay}), 규칙은 {@code schedule_exception} 으로 그날을 건너뛴다.
 * 그래서 <b>완료 표시는 그날 하나에만</b> 붙고 규칙 전체가 완료되지 않는다.
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
    private final ScheduleExceptionRepository exceptions;
    private final DogOwnership dogs;
    private final ChatRoomService chatRooms;
    private final KnownUsers users;
    private final CareLogging careLogging;
    private final Clock clock;

    public ScheduleService(ScheduleRepository schedules,
                           ScheduleExceptionRepository exceptions,
                           DogOwnership dogs,
                           ChatRoomService chatRooms,
                           KnownUsers users,
                           CareLogging careLogging,
                           Clock clock) {
        this.schedules = schedules;
        this.exceptions = exceptions;
        this.dogs = dogs;
        this.chatRooms = chatRooms;
        this.users = users;
        this.careLogging = careLogging;
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
                .repeatKind(request.repeatKind() == null
                        ? ScheduleRepeat.NONE : request.repeatKind())
                .repeatUntil(request.repeatKind() != null && request.repeatKind().repeats()
                        ? request.repeatUntil() : null)
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

        return apply(schedule, me, request);
    }

    /**
     * 요청을 그대로 적용한다 — <b>버전을 안 본다</b>.
     *
     * <p>{@link #update} 에서 갈라 낸 이유는 {@link #overrideOneDay} 때문이다. 거기서는
     * 방금 만든 행에 요청을 얹는데, 그 행은 <b>1밀리초 전에 없던 것</b>이라 남이 고쳤을 수
     * 없다. 그런데도 버전을 보면, 그 사이에 예외 저장이 flush 를 일으켜 버전이 올라가
     * <b>이유 없는 409</b> 가 난다(실측으로 걸렸다 — #420 의 두 번 오르기와 같은 자리다).
     *
     * <p>잠금은 {@link #overrideOneDay} 가 <b>규칙의 버전</b>으로 이미 걸었다.
     */
    private ScheduleResponse apply(Schedule schedule, User me, ScheduleUpdateRequest request) {
        long userId = me.getId();
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

        if (request.repeatKind() != null) {
            // memo 무리와 다른 답이다 — 안 보냈다고 반복을 꺼 버리면 "제목만 고쳤는데
            // 반복이 사라졌다" 가 된다(ScheduleUpdateRequest javadoc).
            schedule.repeatEvery(request.repeatKind(), request.repeatUntil());
        }

        if (request.status() != null && request.status() != schedule.getStatus()) {
            schedule.markStatus(request.status(), ScheduleTime.nowUtc(clock), me);
            syncCareLog(schedule, me);
        }

        return ScheduleResponse.of(schedules.saveAndFlush(schedule));
    }

    /**
     * 규칙의 <b>하루만</b> 고친다 — 이슈 #421.
     *
     * <p>그날짜용 행을 하나 만들고, 규칙에는 {@code override} 예외를 남겨 그날을 건너뛰게
     * 한다. 그 행은 되풀이하지 않는 평범한 일정이라 자기 날짜로 조회되고, 완료·되돌리기가
     * 그 하나에만 붙는다.
     *
     * <p><b>버전은 규칙의 것을 본다.</b> 펼친 하루에는 자기 버전이 없기 때문이다. 그래서
     * 화요일 것을 고치는 사이 누가 규칙을 고치면 409 를 받는다 — 서로 다른 날을 고치는
     * 두 사람도 마찬가지다. 덮어쓰는 것보다 한 번 더 묻는 쪽이 낫다고 보았다.
     *
     * @param day 규칙이 <b>실제로 오는 날</b>이어야 한다. 아니면 404 다 — 오지도 않는 날에
     *            예외를 만들면 그 줄이 영원히 아무 일도 안 한다
     */
    @Transactional
    public ScheduleResponse overrideOneDay(User me, long scheduleId, int version, LocalDate day,
                                           ScheduleUpdateRequest request) {
        long userId = me.getId();
        Schedule rule = requireRuleComingOn(userId, scheduleId, day);

        if (rule.getVersion() != version) {
            throw new StaleScheduleException(ScheduleResponse.of(rule));
        }

        Schedule copy = schedules.save(Schedule.builder()
                .ownerKind(rule.getOwnerKind())
                .ownerRef(rule.getOwnerRef())
                .dog(rule.getDog())
                .kind(rule.getKind())
                .title(rule.getTitle())
                .memo(rule.getMemo())
                .onDate(day)
                .atTime(rule.getAtTime())
                .assignee(rule.getAssignee())
                .status(ScheduleStatus.PLANNED)
                .repeatKind(ScheduleRepeat.NONE)
                .createdBy(me)
                .build());
        copy.replacesOneDayOf(rule);

        exceptions.save(ScheduleException.builder()
                .schedule(rule)
                .onDate(day)
                .kind(ScheduleExceptionKind.OVERRIDE)
                .build());

        // 만든 행에 요청을 그대로 적용한다 — 버전은 안 본다(apply 의 javadoc).
        return apply(copy, me, request);
    }

    /**
     * 규칙의 <b>하루만</b> 건너뛴다 — 이슈 #421. 대신할 행을 안 만든다.
     *
     * <p>규칙 자체는 그대로다. "이번 주만 안 함" 이 반복을 지우는 일이 되면 안 된다.
     */
    @Transactional
    public void skipOneDay(long userId, long scheduleId, LocalDate day) {
        Schedule rule = requireRuleComingOn(userId, scheduleId, day);

        // 이미 예외가 있으면 그대로 둔다 — 건너뛴 날을 또 건너뛰는 것은 아무 일도 아니다.
        if (exceptions.findOne(rule.getId(), day).isEmpty()) {
            exceptions.save(ScheduleException.builder()
                    .schedule(rule)
                    .onDate(day)
                    .kind(ScheduleExceptionKind.SKIP)
                    .build());
        }
    }

    /** 내 규칙이고 그날 실제로 오는가. 아니면 <b>같은 404</b> 다. */
    private Schedule requireRuleComingOn(long userId, long scheduleId, LocalDate day) {
        Schedule rule = mine(userId, scheduleId);
        if (!rule.isRule()) {
            throw notFound();
        }
        Set<LocalDate> already = exceptions.findOne(rule.getId(), day)
                .map(e -> Set.of(e.getOnDate()))
                .orElse(Set.of());
        if (ScheduleExpansion.datesOf(rule, day, day, already).isEmpty()) {
            throw notFound();
        }
        return rule;
    }

    /**
     * 지운다. <b>케어 기록은 거두지 않는다</b> — 이슈 #420.
     *
     * <p>되돌리기({@code planned} 로)와 다른 답인 것이 의도다. 되돌리기는 "그 일이 일어나지
     * 않았다" 는 말이지만, 지우기는 <b>"이 계획을 더 안 본다"</b> 는 말이다. 이미 다녀온
     * 병원의 기록까지 함께 사라지면, 계획을 정리하다 사실을 잃는다.
     */
    @Transactional
    public void delete(long userId, long scheduleId) {
        schedules.delete(mine(userId, scheduleId));
    }

    /**
     * 상태가 바뀐 뒤 케어 기록을 맞춘다 — 이슈 #420.
     *
     * <p><b>완료면 남기고, 아니면 거둔다.</b> {@code skipped} 도 거두는 쪽이다 — "건너뛰었다"
     * 는 하지 않았다는 뜻이라, 그것이 오늘의 케어에 남으면 안 된다.
     *
     * <p>이 메서드는 <b>던지지 않는다.</b> 케어 기록은 곁다리이고, 그것 때문에 일정 완료
     * 자체가 실패하면 사용자는 자기가 한 일을 못 적는다.
     */
    private void syncCareLog(Schedule schedule, User actor) {
        if (schedule.getOwnerKind() != ScheduleOwnerKind.GROUP) {
            // 아이 소유 일정은 넣을 그룹이 없다. care_log 는 그룹 축이다.
            return;
        }
        long groupId = schedule.getOwnerRef();

        Long existing = schedule.getCareLogId();
        if (existing != null) {
            careLogging.withdraw(groupId, existing, actor.getId());
            schedule.linkCareLog(null);
        }

        if (schedule.getStatus() != ScheduleStatus.DONE) {
            return;
        }
        String careWire = schedule.getKind().careWire();
        if (careWire == null) {
            // 미용·목욕·사료·그 밖은 케어 종류가 아니다 — ScheduleKind.careWire javadoc.
            return;
        }
        careLogging.recordFor(groupId, careWire, actor).ifPresent(schedule::linkCareLog);
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

        List<Schedule> mine = found.stream()
                .filter(s -> dogId == null
                        || (s.getDog() != null && dogId.equals(s.getDog().getId())))
                .toList();

        return expand(mine, from, to).stream()
                // 종류가 섞이면 순서가 두 목록의 이어 붙이기가 된다 — 날짜순으로 다시 세운다.
                .sorted(Comparator.comparing(ScheduleResponse::onDate)
                        .thenComparing(ScheduleResponse::atTime,
                                Comparator.nullsLast(Comparator.naturalOrder()))
                        .thenComparing(ScheduleResponse::id))
                .toList();
    }

    /**
     * 규칙을 기간 안의 날짜들로 펼친다 — 이슈 #421.
     *
     * <p>되풀이가 아닌 행은 그대로 한 줄이다. 되풀이하는 행은 {@link ScheduleExpansion} 이
     * 고른 날짜마다 한 줄이 되고, 그 줄들은 <b>행이 아니다</b> —
     * {@code ScheduleResponse.occurrence} 가 그것을 말한다.
     *
     * <p>예외는 <b>한 번에</b> 읽는다. 규칙마다 물으면 한 달 조회의 쿼리가 규칙 수만큼
     * 늘어난다.
     */
    private List<ScheduleResponse> expand(List<Schedule> rows, LocalDate from, LocalDate to) {
        List<Long> ruleIds = rows.stream()
                .filter(Schedule::isRule)
                .map(Schedule::getId)
                .toList();

        Map<Long, Set<LocalDate>> skipped = new HashMap<>();
        if (!ruleIds.isEmpty()) {
            for (ScheduleException e : exceptions.findRange(ruleIds, from, to)) {
                skipped.computeIfAbsent(e.getSchedule().getId(), id -> new HashSet<>())
                        .add(e.getOnDate());
            }
        }

        List<ScheduleResponse> out = new ArrayList<>();
        for (Schedule row : rows) {
            if (!row.isRule()) {
                out.add(ScheduleResponse.of(row));
                continue;
            }
            Set<LocalDate> mine = skipped.getOrDefault(row.getId(), Set.of());
            for (LocalDate day : ScheduleExpansion.datesOf(row, from, to, mine)) {
                out.add(ScheduleResponse.occurrenceOf(row, day));
            }
        }
        return out;
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

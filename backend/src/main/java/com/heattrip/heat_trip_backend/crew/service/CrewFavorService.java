package com.heattrip.heat_trip_backend.crew.service;

import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.crew.dto.CrewFavorRequest;
import com.heattrip.heat_trip_backend.crew.dto.CrewFavorResponse;
import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavor;
import com.heattrip.heat_trip_backend.crew.repository.CrewFavorRepository;
import com.heattrip.heat_trip_backend.crew.repository.CrewRepository;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.schedule.CrewSchedules;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Objects;

/**
 * 품앗이 — 서로 맡아 주기. 이슈 #417.
 *
 * <h2>돈이 안 붙는다 — 그것이 이 기능의 크기를 정한다</h2>
 * <p>이슈가 스스로 그은 선이다. <b>결제·평점·보증·중개는 안 한다.</b> 돈이 오가는 순간
 * 우리는 중개자가 되고, 사고가 나면 배상 책임과 신고 의무가 따라온다. 그래서 여기서 하는
 * 일은 <b>약속을 적는 것</b>까지다 — 실제로 몇 시에 어디서 만날지는 크루 대화방에서 정한다.
 *
 * <h2>맡으면 달력에 한 줄이 남는다</h2>
 * <p>이것이 이 기능의 알맹이다. 크루 화면에만 두면 <b>그날 아침에 아무도 그것을 안 본다</b> —
 * 사람은 아침에 달력을 보지 크루 목록을 보지 않는다. 그래서 맡는 순간 크루 소유 일정
 * ({@code owner_kind=room})이 하나 생기고, 그 줄은 그 크루 사람 모두의 달력에 뜬다.
 *
 * <p>무르면 그 줄을 거둔다. 안 거두면 아무도 안 하기로 한 일이 그날 아침에 뜬다.
 *
 * <h2>방향 — 여기서 schedule 을 부른다. 그 반대는 없다</h2>
 * <p>{@code schedule} 은 크루 일정의 권한을 잴 때 {@code crew} 를 <b>안 부른다</b>. 부르면
 * 고리가 되고 {@code ModuleCycleTest} 가 잡는다({@code CrewSchedules} javadoc).
 */
@Service
@RequiredArgsConstructor
public class CrewFavorService {

    /**
     * 크루 홈이 한 번에 받는 부탁 수. 무한 스크롤을 아직 안 만든다 — 동네 모임 하나에
     * 앞으로 올 부탁이 50건을 넘는 상태가 오면 그때 커서를 단다.
     */
    static final int PAGE = 50;

    /** 일정 제목의 기본값. 아이를 안 고른 부탁이다. */
    static final String UNTITLED = "품앗이";

    private final CrewFavorRepository favors;
    private final CrewRepository crews;
    private final ChatRoomService chatRooms;
    private final DogOwnership dogs;
    private final CrewSchedules schedules;
    private final Clock clock;

    /**
     * 그 크루의 부탁 목록. <b>멤버만</b> 본다.
     *
     * <p>공개 크루라도 안 든 사람에게는 404 다 — 부탁에는 아이 이름과 "그날 집을 비운다" 가
     * 함께 적힌다. 인원 수까지가 공개인 것과 같은 선이다({@code CrewService.detail}).
     */
    @Transactional(readOnly = true)
    public List<CrewFavorResponse> list(long crewId, User me) {
        requireMember(crewId, me.getId());
        return favors.findUpcoming(crewId, today(), Limit.of(PAGE)).stream()
                .map(favor -> CrewFavorResponse.of(favor, me.getId()))
                .toList();
    }

    /**
     * 부탁을 올린다. <b>멤버만.</b>
     *
     * <p>지난 날짜는 400 이다 — 아무도 못 맡는 부탁이 목록의 위쪽을 막는다.
     *
     * <p>아이는 <b>내 아이</b>여야 한다. 아니면 404 다({@code DogOwnership} 규약). 여기서
     * 한 번 확인하고 행을 들어 두는 이유는, 맡는 사람 눈으로는 그 아이가 남의 것이라
     * 나중에는 확인할 수 없기 때문이다.
     */
    @Transactional
    public CrewFavorResponse post(long crewId, User me, CrewFavorRequest request) {
        Crew crew = requireMember(crewId, me.getId());

        if (request.onDate().isBefore(today())) {
            throw new IllegalArgumentException("지난 날짜로는 부탁할 수 없습니다.");
        }

        // 우리 집 아이면 된다(#563) — 아빠가 엄마의 보리 산책을 부탁할 수 있어야 한다.
        Dog dog = request.dogId() == null
                ? null
                : dogs.requireInHouseholdEntity(me.getId(), request.dogId());

        CrewFavor saved = favors.save(CrewFavor.builder()
                .crew(crew)
                .askedBy(me)
                .dog(dog)
                .onDate(request.onDate())
                .slot(request.slot())
                .note(blankToNull(request.note()))
                .build());
        return CrewFavorResponse.of(saved, me.getId());
    }

    /**
     * "제가 할게요". <b>멤버만</b>이고 <b>한 명만</b>이다.
     *
     * <p>이미 맡은 것은 409 다 — 둘이 같은 약속을 맡으면 부탁한 사람은 누가 오는지 모른다.
     *
     * <p><b>자기 부탁은 못 맡는다</b>(400). 맡을 수 있게 두면 달력에 "내가 나에게 맡긴 일"
     * 한 줄이 생기고, 그 줄은 아무 뜻도 없다.
     *
     * <p>맡는 순간 크루 일정 한 줄이 생긴다 — 클래스 javadoc 참조.
     */
    @Transactional
    public CrewFavorResponse take(long crewId, long favorId, User me) {
        requireMember(crewId, me.getId());
        CrewFavor favor = favorOf(crewId, favorId);

        if (!favor.isOpen()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "이미 다른 분이 맡았습니다.");
        }
        if (isMe(favor.getAskedBy(), me.getId())) {
            throw new IllegalArgumentException("내가 올린 부탁은 내가 맡을 수 없습니다.");
        }

        long scheduleId = schedules.line(
                crewId, favor.getOnDate(), titleOf(favor), memoOf(favor), favor.getDog(), me);
        favor.takenBy(me, scheduleId);
        return CrewFavorResponse.of(favors.save(favor), me.getId());
    }

    /**
     * 무른다. <b>맡은 사람만.</b> 달력의 줄도 함께 거둔다.
     *
     * <p>부탁한 사람이 무르는 것이 아니다 — 그건 {@link #cancel} 이다. 둘을 한 경로로 묶으면
     * "누가 무른 것인가" 가 조건문 하나에 숨는다.
     */
    @Transactional
    public CrewFavorResponse release(long crewId, long favorId, User me) {
        requireMember(crewId, me.getId());
        CrewFavor favor = favorOf(crewId, favorId);

        if (!isMe(favor.getTakenBy(), me.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "맡은 분만 무를 수 있습니다.");
        }

        schedules.remove(favor.getScheduleId());
        favor.released();
        return CrewFavorResponse.of(favors.save(favor), me.getId());
    }

    /**
     * 부탁을 거둬들인다. <b>올린 사람만.</b>
     *
     * <p>이미 맡은 부탁도 지울 수 있다 — 사정이 생겨 안 맡겨도 되는 날이 있다. 그때 달력의
     * 줄도 함께 사라진다. 맡은 사람에게는 그 줄이 없어지는 것이 곧 알림이다(서버 푸시는 #83).
     *
     * <p>상태로 "취소됨" 을 남기지 않는다 — 목록이 안 지워지는 카드로 점점 길어진다.
     */
    @Transactional
    public void cancel(long crewId, long favorId, User me) {
        requireMember(crewId, me.getId());
        CrewFavor favor = favorOf(crewId, favorId);

        if (!isMe(favor.getAskedBy(), me.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "올린 분만 지울 수 있습니다.");
        }

        schedules.remove(favor.getScheduleId());
        favors.delete(favor);
    }

    /**
     * 크루가 사라질 때 그 크루의 부탁과 <b>달력 줄까지</b> 거둔다 — {@code CrewService.delete}
     * 가 부른다.
     *
     * <p>DB 의 {@code ON DELETE CASCADE} 가 행은 지우지만 <b>일정은 다른 표</b>다. 안 거두면
     * 없는 크루의 약속이 사람들 달력에 남는다.
     */
    @Transactional
    public void removeAllOf(long crewId) {
        List<CrewFavor> all = favors.findAllOfCrew(crewId);
        all.forEach(favor -> schedules.remove(favor.getScheduleId()));
        favors.deleteAll(all);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 달력에 뜰 제목. <b>아이 이름이 먼저다</b> — "보리 봐 주기" 가 "품앗이" 보다 그날 아침에
     * 훨씬 잘 읽힌다.
     */
    static String titleOf(CrewFavor favor) {
        return favor.getDog() == null ? UNTITLED : favor.getDog().getName() + " 봐 주기";
    }

    /**
     * 달력 줄의 메모. <b>시간대가 여기 들어간다</b> — 일정의 {@code at_time} 을 0시로 채우면
     * 달력이 그것을 "새벽 12시" 로 그린다({@code CrewFavorSlot} javadoc).
     */
    static String memoOf(CrewFavor favor) {
        String slot = favor.getSlot().label();
        return favor.getNote() == null ? slot : slot + " · " + favor.getNote();
    }

    /**
     * 그 크루의 부탁 하나. <b>다른 크루의 id 를 넣으면 404</b> 다 — 경로의 크루와 부탁이
     * 안 맞는 것을 안 재면, 멤버인 크루 하나로 남의 크루 부탁을 만질 수 있다.
     */
    private CrewFavor favorOf(long crewId, long favorId) {
        CrewFavor favor = favors.findById(favorId)
                .orElseThrow(() -> new NoSuchElementException("부탁을 찾을 수 없습니다."));
        if (favor.getCrew() == null || favor.getCrew().getId() != crewId) {
            throw new NoSuchElementException("부탁을 찾을 수 없습니다.");
        }
        return favor;
    }

    /**
     * 그 사람이 나인가 — 부탁을 맡고 · 무르고 · 거둬들이는 <b>세 자리가 함께 쓰는 판정</b>이다.
     *
     * <p><b>{@code ==} 가 아니다.</b> 양쪽 다 {@code Long} 이라 언박싱이 없고, 그러면 값이 아니라
     * 참조를 견주게 된다(#510). 지금까지 통과한 이유는 {@code spring.jpa.open-in-view} 가 어디에도
     * 안 적혀 있어 기본값 {@code true} 이고, 요청 하나가 영속성 컨텍스트를 공유해 Hibernate 가
     * 같은 {@code User} 인스턴스를 돌려주기 때문이다. <b>그 설정을 끄는 날</b> id 가 127 을 넘는
     * 사용자는 무르기·거둬들이기가 전원 403 이 되고("자기 부탁은 자기가 못 맡는다" 는 반대로
     * 풀린다) — {@code Long} 캐시가 그 위로는 없다. 같은 저장소의 다른 소유권 검사는 전부
     * {@code equals} 이거나 primitive 언박싱이다.
     *
     * <p>{@code null} 이면 거짓이다 — 아무도 안 맡은 부탁의 {@code takenBy} 가 그렇다.
     */
    static boolean isMe(User who, Long meId) {
        return who != null && Objects.equals(who.getId(), meId);
    }

    /** 그 크루의 살아 있는 멤버인가. 아니거나 크루가 없으면 <b>같은 404</b> 다. */
    private Crew requireMember(long crewId, long userId) {
        Crew crew = crews.findById(crewId)
                .orElseThrow(() -> new NoSuchElementException("크루를 찾을 수 없습니다."));
        ChatRoomView room = chatRooms
                .findRoom(CrewService.ORIGIN_KIND, String.valueOf(crewId))
                .orElseThrow(() -> new NoSuchElementException("크루를 찾을 수 없습니다."));
        if (!chatRooms.isLiveMember(room.id(), userId)) {
            throw new NoSuchElementException("크루를 찾을 수 없습니다.");
        }
        return crew;
    }

    /** 사용자의 오늘(KST). 시계 빈은 {@code Asia/Seoul} 이다. */
    private LocalDate today() {
        return LocalDate.now(clock.withZone(ZoneId.of("Asia/Seoul")));
    }

    private static String blankToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.strip();
        return trimmed.isEmpty() ? null : trimmed;
    }
}

package com.heattrip.heat_trip_backend.crew.service;

import com.heattrip.heat_trip_backend.chat.ChatJoinResult;
import com.heattrip.heat_trip_backend.chat.ChatMemberView;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.crew.dto.CrewPatch;
import com.heattrip.heat_trip_backend.crew.dto.CrewRequest;
import com.heattrip.heat_trip_backend.crew.dto.CrewResponse;
import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewVisibility;
import com.heattrip.heat_trip_backend.crew.repository.CrewRepository;
import com.heattrip.heat_trip_backend.user.KnownUsers;
import com.heattrip.heat_trip_backend.user.NeighborhoodCatalog;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.Set;

/**
 * 동네 반려인 모임 — 이슈 #417. 근거 ADR-0011.
 *
 * <h2>크루는 방 위에 얹는 것이지 새로 만드는 것이 아니다</h2>
 * <p>{@code chat_room} 은 처음부터 <b>범용 다중 방</b>으로 서 있었다 — {@code origin_kind} 와
 * {@code origin_ref} 로 출처를 불투명하게 들고, 그 컬럼 주석이 이미 "가족방도 산책 크루 방도
 * 같은 표에 산다" 고 적고 있었다. 그래서 방·멤버십·초대·메시지·미읽음은 하나도 새로 안 만든다.
 * {@code crew} 표가 더하는 것은 <b>이름·소개·동네·공개 범위·정원</b> 다섯뿐이다.
 *
 * <h2>방향 — 여기서 chat 을 부른다. 그 반대는 없다</h2>
 * <p>{@code FamilyGroupService} 가 고른 방향과 같고 이유도 같다. {@code crew} 행을 INSERT 하는
 * 코드가 저장소 전체에 {@link #create} 하나뿐이고, 그 메서드가 같은 트랜잭션에서 방과
 * {@code OWNER} 를 만든다. <b>문이 하나면 그 문에서만 지키면 된다</b> — "방 없는 크루" 라는
 * 상태가 만들어질 자리가 없다.
 *
 * <h2>방장이 누구인지 이 표는 모른다</h2>
 * <p>{@code crew} 에 {@code owner_user_id} 컬럼을 두지 않았다. 방장은 <b>그 방의 {@code OWNER}
 * 멤버</b>이고 그것은 {@code chat_room_member.role} 이다. 컬럼을 따로 두면 둘이 갈리는 날이
 * 오고, 그날 "크루 화면에서는 방장인데 대화방에서는 못 내보내는" 사람이 생긴다.
 *
 * <h2>만 14세 미만은 크루에 못 들어온다</h2>
 * <p>{@code MinorRoomPolicy} 가 이미 정해 둔 선이다 — 미성년 계정이 들어갈 수 있는 방은
 * {@code FAMILY} 뿐이다. 그 정책은 <b>초대코드 참여 경로에만</b> 걸려 있었으므로, 크루를
 * <b>만드는</b> 경로와 <b>공개 참여</b> 경로에서는 여기서 다시 잰다. 안 재면 만 13세가
 * 크루를 만들어 방 하나를 열고 그 방에 자기가 들어앉는다.
 */
@Service
@RequiredArgsConstructor
public class CrewService {

    /**
     * 이 도메인이 방에 자기를 밝히는 이름. {@code chat_room.origin_kind} 에 그대로 들어간다.
     *
     * <p>chat 은 이 문자열을 <b>해석하지 않는다</b>({@code FamilyGroupService.ORIGIN_KIND} 와
     * 같은 규약). 뜻은 여기서만 안다.
     */
    public static final String ORIGIN_KIND = "CREW";

    /**
     * 화면이 방 종류를 표시할 때 쓰는 이름표.
     *
     * <p>이슈 본문은 {@code tag='crew'} 라고 적었지만 <b>이 컬럼은 사람이 읽는 라벨</b>이다 —
     * 가족방이 {@code "가족"} 을 쓰고 앱의 채팅 목록이 그 값을 그대로 그린다. 여기만 영어면
     * 목록에 "가족" 과 "crew" 가 나란히 뜬다.
     */
    static final String ROOM_TAG = "크루";

    /** {@code crew.name} · {@code chat_room.name} 둘 다에 들어가는 값이라 짧은 쪽에 맞춘다. */
    static final int MAX_NAME_LENGTH = 30;

    static final int MAX_INTRO_LENGTH = 200;

    /**
     * 우리 동네 목록의 한 판. 무한 스크롤을 아직 안 만든다 — 동네 하나에 크루가 50개를
     * 넘는 상태가 오면 그때 커서를 단다(커뮤니티가 그렇게 하고 있다).
     */
    static final int NEIGHBOURHOOD_PAGE = 50;

    private static final String OWNER_ROLE = "OWNER";

    private final CrewRepository crews;
    private final ChatRoomService chatRooms;
    private final KnownUsers knownUsers;
    private final NeighborhoodCatalog neighborhoods;

    /** 크루를 지울 때 품앗이의 달력 줄까지 거두는 자리 — {@link #delete} javadoc. */
    private final CrewFavorService favors;

    // ─────────────────────────── 만들기 ───────────────────────────

    /**
     * 크루를 만든다. <b>같은 트랜잭션에서 방과 {@code OWNER} 멤버십이 함께 생긴다.</b>
     *
     * <p>{@code @Transactional} 이 여기 있고 {@link ChatRoomService#openRoom} 은 전파 기본값
     * ({@code REQUIRED})이라 같은 트랜잭션에 들어온다. 방 생성이 실패하면 크루 행도 함께
     * 롤백된다 — 완료 조건 1 이 요구하는 성질이 이것이다.
     *
     * <p>{@code saveAndFlush} 로 id 를 먼저 받는다 — 그 id 가 방의 {@code origin_ref} 다.
     *
     * <p><b>가족과 달리 개수를 안 막는다.</b> 가족 그룹은 {@code GET /api/groups/me} 가 단수라
     * 두 번째가 유령이 됐지만, 크루 목록은 처음부터 복수다. 동네 모임을 둘 드는 것은 정상이다.
     */
    @Transactional
    public CrewResponse create(User me, CrewRequest request) {
        requireCrewsAreOpenTo(me);

        String name = validName(request.name());
        String intro = validIntro(request.intro());
        CrewVisibility visibility =
                request.visibility() == null ? CrewVisibility.INVITE : request.visibility();
        String neighborhood = myNeighborhoodUnlessGiven(request.neighborhoodCode(), me);
        requirePublicCrewsHaveANeighborhood(neighborhood, visibility);
        int capacity = request.capacity() == null ? Crew.DEFAULT_CAPACITY : request.capacity();

        Crew crew = crews.saveAndFlush(Crew.builder()
                .name(name)
                .intro(intro)
                .neighborhoodCode(neighborhood)
                .visibility(visibility)
                .capacity(capacity)
                .build());

        ChatRoomView room = chatRooms.openRoom(
                ORIGIN_KIND, String.valueOf(crew.getId()), name, ROOM_TAG, me.getId());

        return detail(crew, room, OWNER_ROLE);
    }

    // ─────────────────────────── 목록 ───────────────────────────

    /**
     * 내가 든 크루 — 참여 순서대로.
     *
     * <p>이 답은 {@code crew} 표가 아니라 {@code chat_room_member} 에서 나온다. 멤버십 표가
     * 하나이기 때문이다(ADR-0011 결정 1). 방 목록을 받아 {@code origin_ref} 로 크루 행을
     * 되찾는다.
     *
     * <p><b>쿼리는 크루 개수와 무관하게 넷</b>이다 — 내 방들 · 크루 행들 · 방별 인원 ·
     * 내 역할. 카드마다 방을 찾으면 그것이 N+1 이다.
     */
    @Transactional(readOnly = true)
    public List<CrewResponse> mine(long userId) {
        List<ChatRoomView> rooms = chatRooms.roomsOfMember(ORIGIN_KIND, userId);
        return listOf(rooms, crewsOf(rooms), userId);
    }

    /**
     * 우리 동네 공개 크루 — 최근에 만든 것부터. 완료 조건 3.
     *
     * <p><b>좌표를 안 쓴다.</b> 시군구 앞 다섯 자리로 훑는다(A안 #235 · #342). 그 앞자리는
     * 사용자가 스스로 고른 행정동 코드에서 잘라 낸 값이라 위치정보가 아니다.
     *
     * <p>내가 이미 든 공개 크루도 목록에 남는다 — 빼면 "분명 있었는데 없어졌다" 가 된다.
     * 대신 {@code mine} 이 {@code true} 라 카드가 "들어가기" 를 그린다.
     */
    @Transactional(readOnly = true)
    public List<CrewResponse> nearby(User me) {
        String sgg = NeighborhoodCatalog.sggPrefixOf(me.getNeighborhoodCode());
        if (sgg == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "동네를 먼저 골라 주세요.");
        }

        List<Crew> found = crews.findPublicIn(
                CrewVisibility.PUBLIC, sgg, Limit.of(NEIGHBOURHOOD_PAGE));
        Map<Long, Crew> byId = new LinkedHashMap<>();
        found.forEach(crew -> byId.put(crew.getId(), crew));

        List<ChatRoomView> rooms = chatRooms.findRooms(ORIGIN_KIND, refsOf(byId.keySet()));
        // 방 목록의 순서는 보장이 없다. 목록의 순서는 crew 쪽(최근 순)이 정한다.
        Map<Long, ChatRoomView> roomByCrew = new LinkedHashMap<>();
        for (ChatRoomView room : rooms) {
            crewIdOf(room).ifPresent(id -> roomByCrew.put(id, room));
        }
        List<ChatRoomView> ordered = new ArrayList<>();
        for (Long id : byId.keySet()) {
            ChatRoomView room = roomByCrew.get(id);
            if (room != null) {
                ordered.add(room);
            }
        }

        return listOf(ordered, byId, me.getId());
    }

    /**
     * 크루 홈 하나.
     *
     * <h2>초대 크루는 멤버가 아니면 <b>404</b> 다 — 403 이 아니다</h2>
     * <p>403 은 "여기 있는데 너는 못 본다" 라고 말한다. 그러면 id 를 하나씩 넣어 보는 것만으로
     * 어느 번호에 크루가 있는지 세어진다 — 이름은 못 보더라도 <b>존재는 샌다</b>. 공개 범위가
     * 초대인 모임에서 그것은 그 자체로 새는 것이다.
     *
     * <p>공개 크루는 안 든 사람도 본다 — 안 그러면 들어갈지 말지 정할 수가 없다. 다만
     * <b>멤버 목록은 안 준다</b>. 인원 수까지가 공개고 누가 있는지는 안에서만이다.
     */
    @Transactional(readOnly = true)
    public CrewResponse detail(long crewId, User me) {
        Crew crew = crewOrNotFound(crewId);
        ChatRoomView room = roomOrNotFound(crewId);
        String myRole = roleOf(room.id(), me.getId());

        if (myRole == null && !crew.getVisibility().isPublic()) {
            throw new NoSuchElementException("크루를 찾을 수 없습니다.");
        }
        return detail(crew, room, myRole);
    }

    // ─────────────────────────── 고치기 · 강퇴 ───────────────────────────

    /**
     * 방장이 크루를 고친다. 완료 조건 4.
     *
     * <p><b>방 이름도 함께 고친다.</b> 안 그러면 크루 이름을 바꾼 사람의 채팅 목록에 옛 이름이
     * 남아 같은 모임이 화면 두 곳에서 다르게 보인다({@code ChatRoomService#renameRoom}).
     *
     * <p>{@code renameRoom} 이 방장 여부를 <b>다시</b> 잰다. 중복이 아니라 그 메서드의 계약이다 —
     * 여기서 안 재고 그쪽만 믿으면 이름을 안 바꾸는 수정에서는 아무도 안 재게 된다.
     */
    @Transactional
    public CrewResponse edit(long crewId, User me, CrewPatch patch) {
        if (patch.isEmpty()) {
            throw new IllegalArgumentException("고칠 것을 하나 이상 보내 주세요.");
        }

        Crew crew = crewOrNotFound(crewId);
        ChatRoomView room = roomOrNotFound(crewId);
        requireOwner(room.id(), me.getId());

        // null 은 "안 바꾼다" 다 — 빈 문자열("지운다")과 다르다(CrewPatch javadoc).
        String name = patch.name() == null ? crew.getName() : validName(patch.name());
        String intro = patch.intro() == null ? crew.getIntro() : validIntro(patch.intro());
        CrewVisibility visibility =
                patch.visibility() == null ? crew.getVisibility() : patch.visibility();
        String neighborhood = patch.neighborhoodCode() == null
                ? crew.getNeighborhoodCode()
                : knownNeighborhood(patch.neighborhoodCode());
        int capacity = patch.capacity() == null ? crew.getCapacity() : patch.capacity();
        requirePublicCrewsHaveANeighborhood(neighborhood, visibility);

        crew.edit(name, intro, neighborhood, visibility, capacity);
        crews.saveAndFlush(crew);

        ChatRoomView renamed = name.equals(room.name())
                ? room
                : chatRooms.renameRoom(room.id(), me.getId(), name);

        return detail(crew, renamed, OWNER_ROLE);
    }

    /** 방장이 멤버를 내보낸다. 방장이 아니면 403, 그 방에 없는 사람이면 404 — chat 이 잰다. */
    @Transactional
    public void kick(long crewId, User me, long targetUserId) {
        chatRooms.removeMember(roomOrNotFound(crewId).id(), me.getId(), targetUserId);
    }

    /**
     * 방장을 넘긴다. <b>방장만.</b> 이슈 #417.
     *
     * <p>{@link #leave} 가 방장을 막기 때문에 이것이 있어야 한다 — 막는 쪽만 만들고 푸는
     * 쪽을 안 만들면 크루를 만든 사람은 영영 못 나간다. 넘기고 나면 평범한 멤버라 나갈 수
     * 있다.
     *
     * <p>판정은 전부 {@code chat} 이 한다 — 역할이 사는 곳이 거기다.
     */
    @Transactional
    public CrewResponse transferOwner(long crewId, User me, long targetUserId) {
        Crew crew = crewOrNotFound(crewId);
        ChatRoomView room = roomOrNotFound(crewId);

        chatRooms.transferOwner(room.id(), me.getId(), targetUserId);

        // 넘긴 뒤의 나는 방장이 아니다. 역할 지도를 다시 읽어야 화면이 그것을 바로 안다.
        return detail(crew, room, roleOf(room.id(), me.getId()));
    }

    /**
     * 크루를 지운다. <b>방장이 혼자 남았을 때만.</b> 이슈 #417.
     *
     * <h2>왜 "혼자일 때만" 인가</h2>
     * <p>방을 지우면 대화가 함께 사라진다. 남의 대화를 지우는 버튼은 만들면 안 된다.
     * 혼자일 때는 그 문제가 없고, <b>그때가 실제로 필요한 때</b>다 — 아무도 안 들어온 모임을
     * 만든 사람이 그것을 치우고 싶은 것이다. 사람이 있으면 넘기면 된다
     * ({@link #transferOwner}).
     *
     * <h2>순서가 있다</h2>
     * <ol>
     *   <li><b>품앗이의 달력 줄부터 거둔다.</b> {@code crew_favor} 는 {@code ON DELETE
     *       CASCADE} 로 함께 사라지지만 <b>일정은 다른 표</b>다 — 안 거두면 없는 크루의
     *       약속이 사람들 달력에 남는다.</li>
     *   <li><b>방을 지운다.</b> 여기서 "혼자인가" 가 판정된다 — 세는 곳이 그곳이라 세는
     *       순간과 지우는 순간이 안 갈라진다. 아니면 409 로 여기서 멈춘다.</li>
     *   <li><b>크루 행을 지운다.</b></li>
     * </ol>
     *
     * <p>2번이 던지면 트랜잭션이 통째로 되돌아가므로 1번의 거둠도 없던 일이 된다.
     */
    @Transactional
    public void delete(long crewId, User me) {
        Crew crew = crewOrNotFound(crewId);
        ChatRoomView room = roomOrNotFound(crewId);

        favors.removeAllOf(crewId);
        chatRooms.deleteRoomIfSoleMember(room.id(), me.getId());
        crews.delete(crew);
    }

    // ─────────────────────────── 참여 · 나가기 ───────────────────────────
    // ─────────────────────────── 참여 · 나가기 ───────────────────────────

    /**
     * 초대 코드로 들어온다. 완료 조건 2.
     *
     * <p>{@code Set.of(ORIGIN_KIND)} 를 주므로 <b>가족방 코드로는 이 경로를 못 지나간다</b> —
     * chat 이 방의 {@code origin_kind} 를 대조해 403 을 낸다.
     *
     * <h2>정원은 참여 <b>뒤에</b> 잰다 — 그리고 그것이 맞다</h2>
     * <p>{@code chat} 의 정원({@code ChatLimits})은 서비스 전체의 상한이고, 크루 정원은 방장이
     * 정한 값이다. 둘은 뜻이 다르므로 크루 정원은 여기서 잰다.
     *
     * <p>먼저 세고 나서 들어가면 세는 순간과 들어가는 순간이 갈라진다. 반대로 <b>들어간 뒤에</b>
     * 세면 그 셈이 정확하다 — {@code joinByInviteCode} 가 {@code lockForMemberChange} 로 방을
     * 잠그고 시작하고, 그 잠금은 <b>바깥 트랜잭션이 커밋될 때까지</b> 풀리지 않는다. 즉 이
     * 메서드가 세는 동안 같은 방에 다른 사람이 들어올 수 없다. 넘치면 예외가 트랜잭션을
     * 통째로 되돌리므로 <b>못 들어온 요청은 초대코드 사용 횟수도 안 쓴다.</b>
     *
     * <h2>격리 수준을 여기서도 낮춘다 — 안 낮추면 안쪽의 것이 무효가 된다</h2>
     * <p>{@code joinByInviteCode} 는 {@code READ_COMMITTED} 를 선언하지만, <b>이미 열린
     * 트랜잭션에 참여할 때는 그 선언이 무시된다</b>(스프링의 {@code validateExistingTransaction}
     * 기본값이 {@code false} 라 예외조차 안 난다). 그러면 바깥의 {@code REPEATABLE READ}
     * 스냅샷이 이 요청 전체를 덮어, 잠금을 기다린 보람 없이 <b>기다리는 동안 커밋된 것을
     * 못 보게 된다</b> — 그 메서드 javadoc 이 적어 둔 데드락·500 이 그 상태에서 나왔다.
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public CrewResponse joinByCode(String code, User me) {
        requireCrewsAreOpenTo(me);

        ChatJoinResult joined = chatRooms.joinByInviteCode(code, me.getId(), Set.of(ORIGIN_KIND));
        Crew crew = crewIdOf(joined.room())
                .flatMap(crews::findById)
                .orElseThrow(() -> new NoSuchElementException("크루를 찾을 수 없습니다."));

        requireWithinCapacity(crew, joined.room().id());
        return detail(crew, joined.room(), roleOf(joined.room().id(), me.getId()));
    }

    /**
     * 공개 크루에 코드 없이 들어온다.
     *
     * <p>초대 크루면 <b>404</b> 다 — {@link #detail} 과 같은 이유로, 있고 없고를 안 흘린다.
     * 이미 든 사람에게는 200 이다(멱등).
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public CrewResponse join(long crewId, User me) {
        requireCrewsAreOpenTo(me);

        Crew crew = crewOrNotFound(crewId);
        ChatRoomView room = roomOrNotFound(crewId);

        if (!crew.getVisibility().isPublic() && roleOf(room.id(), me.getId()) == null) {
            throw new NoSuchElementException("크루를 찾을 수 없습니다.");
        }

        chatRooms.joinRoom(room.id(), me.getId(), Set.of(ORIGIN_KIND));
        requireWithinCapacity(crew, room.id());
        return detail(crew, room, roleOf(room.id(), me.getId()));
    }

    /**
     * 크루를 나간다. 완료 조건 6 — <b>한쪽만 남는 상태가 없다.</b>
     *
     * <p>정확히는 "크루에서도 나가고 방에서도 나간다" 가 아니라, <b>나갈 곳이 하나뿐</b>이다.
     * 크루 멤버십이라는 것이 따로 없고 {@code chat_room_member} 가 전부라, 이 메서드가 하는
     * 일은 그 한 행을 닫는 것이다. 두 곳을 지우는 코드가 아니므로 <b>반만 성공하는 경우가
     * 구조적으로 없다.</b>
     *
     * <p>방장은 못 나간다(400) — 나가면 초대코드도 못 내고 이름도 못 고치는 방이 남는다.
     * 넘기기·지우기는 아직 없다.
     */
    @Transactional
    public void leave(long crewId, User me) {
        chatRooms.leaveRoom(roomOrNotFound(crewId).id(), me.getId());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 만 14세 미만은 크루에 못 들어온다 — {@code MinorRoomPolicy} 와 같은 선.
     *
     * <p>그 정책은 <b>초대코드 경로에만</b> 걸려 있어서, 만들기와 공개 참여는 여기서 잰다.
     */
    private static void requireCrewsAreOpenTo(User me) {
        if (me.isUnder14()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "만 14세 미만은 크루에 참여할 수 없습니다.");
        }
    }

    /**
     * 지금 인원이 정원을 넘었는가. <b>참여 뒤에</b> 부른다 — {@link #joinByCode} javadoc.
     *
     * <p>{@code >} 이지 {@code >=} 가 아니다. 방금 들어온 사람이 이미 세어져 있다.
     */
    private void requireWithinCapacity(Crew crew, long roomId) {
        int now = chatRooms.liveMemberCounts(List.of(roomId)).getOrDefault(roomId, 0);
        if (now > crew.getCapacity()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "크루 정원이 찼습니다.");
        }
    }

    private void requireOwner(long roomId, long userId) {
        if (!OWNER_ROLE.equals(roleOf(roomId, userId))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "방장만 할 수 있습니다.");
        }
    }

    private String roleOf(long roomId, long userId) {
        return chatRooms.myRolesIn(ORIGIN_KIND, userId).get(roomId);
    }

    private Crew crewOrNotFound(long crewId) {
        return crews.findById(crewId)
                .orElseThrow(() -> new NoSuchElementException("크루를 찾을 수 없습니다."));
    }

    /**
     * 크루의 방. <b>없으면 404 다 — 500 이 아니다.</b>
     *
     * <p>{@link #create} 가 둘을 한 트랜잭션에서 만들므로 정상적으로는 없을 수 없다. 그래도
     * 여기서 다루는 이유는, 없을 때 터지면 <b>목록 하나가 통째로 500</b> 이 되기 때문이다.
     */
    private ChatRoomView roomOrNotFound(long crewId) {
        return chatRooms.findRoom(ORIGIN_KIND, String.valueOf(crewId))
                .orElseThrow(() -> new NoSuchElementException("크루를 찾을 수 없습니다."));
    }

    /**
     * {@code origin_ref} 를 크루 id 로 읽는다.
     *
     * <p>chat 에게는 불투명 문자열이지만 <b>이 모듈에게는 자기 id 다</b>. 숫자가 아니면 빈
     * 값이다 — chat 은 이 값의 존재를 확인하지 않으므로(그게 설계다) 남의 방이 섞여 들어와도
     * 500 대신 조용히 빠지는 쪽이 맞다({@code FamilyGroupService.groupOf} 와 같은 판단).
     */
    private static Optional<Long> crewIdOf(ChatRoomView room) {
        try {
            return Optional.of(Long.valueOf(room.originRef()));
        } catch (NumberFormatException notOurs) {
            return Optional.empty();
        }
    }

    private static List<String> refsOf(Iterable<Long> crewIds) {
        List<String> refs = new ArrayList<>();
        crewIds.forEach(id -> refs.add(String.valueOf(id)));
        return refs;
    }

    /** 방 목록 → 크루 행 지도. 한 문장으로 꺼낸다. */
    private Map<Long, Crew> crewsOf(List<ChatRoomView> rooms) {
        List<Long> ids = new ArrayList<>();
        for (ChatRoomView room : rooms) {
            crewIdOf(room).ifPresent(ids::add);
        }
        Map<Long, Crew> byId = new LinkedHashMap<>();
        crews.findAllByIdIn(ids).forEach(crew -> byId.put(crew.getId(), crew));
        return byId;
    }

    /**
     * 카드 목록 한 판. <b>멤버 목록은 안 싣는다</b> — 카드 하나에 사람 스무 명을 실어 나를
     * 이유가 없다({@code CrewResponse.members} javadoc).
     */
    private List<CrewResponse> listOf(List<ChatRoomView> rooms, Map<Long, Crew> byId, long userId) {
        List<Long> roomIds = rooms.stream().map(ChatRoomView::id).toList();
        Map<Long, Integer> counts = chatRooms.liveMemberCounts(roomIds);
        Map<Long, String> roles = chatRooms.myRolesIn(ORIGIN_KIND, userId);

        List<CrewResponse> cards = new ArrayList<>();
        for (ChatRoomView room : rooms) {
            Crew crew = crewIdOf(room).map(byId::get).orElse(null);
            if (crew == null) {
                continue; // 크루 행이 사라진 방. 목록에서 조용히 빠진다
            }
            String role = roles.get(room.id());
            cards.add(CrewResponse.of(crew, room.id(), counts.getOrDefault(room.id(), 0),
                    role != null, OWNER_ROLE.equals(role), List.of()));
        }
        return cards;
    }

    /** 크루 홈 하나. {@code myRole} 이 {@code null} 이면 안 든 사람이라 멤버를 안 준다. */
    private CrewResponse detail(Crew crew, ChatRoomView room, String myRole) {
        int count = chatRooms.liveMemberCounts(List.of(room.id()))
                .getOrDefault(room.id(), 0);

        List<CrewResponse.Member> members = myRole == null ? List.of() : membersOf(room.id());

        return CrewResponse.of(crew, room.id(), count,
                myRole != null, OWNER_ROLE.equals(myRole), members);
    }

    /** 사람 목록 + 이름. 이름은 <b>한 문장</b>으로 모은다({@code KnownUsers.byIds}). */
    private List<CrewResponse.Member> membersOf(long roomId) {
        List<ChatMemberView> live = chatRooms.liveMembers(roomId);
        Map<Long, String> names = new LinkedHashMap<>();
        knownUsers.byIds(live.stream().map(ChatMemberView::userId).toList())
                .forEach(user -> names.put(user.getId(), user.displayName()));

        return live.stream()
                .map(member -> new CrewResponse.Member(
                        member.userId(),
                        names.getOrDefault(member.userId(), User.UNKNOWN_DISPLAY_NAME),
                        member.role()))
                .toList();
    }

    /**
     * 이름 검증. <b>메시지에 입력값을 되싣지 않는다</b> — 이 문구는 그대로 응답 본문이 된다(#6).
     *
     * <p>{@code @Size} 가 앞에서 한 번 거른다. 여기서 또 재는 이유는 이 서비스가 컨트롤러
     * 밖에서도 불릴 수 있고, {@code strip()} 뒤의 길이는 애노테이션이 못 재기 때문이다.
     */
    private static String validName(String requested) {
        String name = requested == null ? "" : requested.strip();
        if (name.isEmpty() || name.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException(
                    "크루 이름은 1자 이상 " + MAX_NAME_LENGTH + "자 이하여야 합니다.");
        }
        return name;
    }

    private static String validIntro(String requested) {
        if (requested == null) {
            return null;
        }
        String intro = requested.strip();
        if (intro.length() > MAX_INTRO_LENGTH) {
            throw new IllegalArgumentException(
                    "소개는 " + MAX_INTRO_LENGTH + "자를 넘을 수 없습니다.");
        }
        return intro.isEmpty() ? null : intro;
    }

    /**
     * 만들 때의 동네 — <b>안 주면 내 동네</b>다. 모임을 만드는 사람은 대개 자기 동네에 만든다.
     *
     * <p>내 동네도 없으면 {@code null} 이고, 그 크루는 어느 동네 목록에도 안 뜬다 —
     * 코드로만 들어온다.
     */
    private String myNeighborhoodUnlessGiven(String requested, User me) {
        return requested == null || requested.isBlank()
                ? me.getNeighborhoodCode()
                : knownNeighborhood(requested);
    }

    /**
     * 고칠 때의 동네 — <b>빈 문자열은 "뗀다"</b> 이고, 그 밖에는 아는 시군구여야 한다.
     *
     * <p>모르는 코드를 안 막으면 아무 문자열이나 저장돼 우리 동네 목록이 조용히 아무것도 안
     * 준다 — 오류가 안 나서 아무도 모른다({@code NeighborhoodCatalog.find} 가 같은 이유로 잰다).
     */
    private String knownNeighborhood(String requested) {
        String code = requested.strip();
        if (code.isEmpty()) {
            return null;
        }
        if (neighborhoods.find(code).isEmpty()) {
            throw new IllegalArgumentException("모르는 동네 코드입니다.");
        }
        return code;
    }

    /**
     * <b>공개 크루는 동네가 있어야 한다.</b>
     *
     * <p>동네 목록이 공개 크루를 찾는 유일한 길이라, 동네 없는 공개 크루는 <b>아무도 못 찾는
     * 공개</b>다. 만들 때도 고칠 때도 같은 자리에서 잰다 — 한쪽만 재면 "만들 때는 막혔는데
     * 고쳐서 그 상태로 갈 수 있는" 문이 남는다.
     */
    private static void requirePublicCrewsHaveANeighborhood(String code, CrewVisibility visibility) {
        if (code == null && visibility.isPublic()) {
            throw new IllegalArgumentException(
                    "공개 크루는 동네를 골라야 합니다. 동네 목록이 찾는 유일한 길입니다.");
        }
    }
}

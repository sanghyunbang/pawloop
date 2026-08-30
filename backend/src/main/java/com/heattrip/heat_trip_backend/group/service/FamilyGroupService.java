package com.heattrip.heat_trip_backend.group.service;

import com.heattrip.heat_trip_backend.chat.ChatMemberView;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.group.dto.GroupMemberResponse;
import com.heattrip.heat_trip_backend.group.dto.GroupResponse;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.group.repository.FamilyGroupRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 가족 그룹을 만들고 조회한다 — 이슈 #75, 근거 ADR-0011.
 *
 * <h2>방향 — 여기서 chat 을 부른다. 그 반대는 없다</h2>
 * <p>세 방향 중 하나를 골라야 했다.
 * <ol>
 *   <li><b>chat 이 group 을 부른다</b> — 불가능하다. {@code ChatBoundaryArchitectureTest} 가
 *       chat 소스에서 다른 도메인 패키지 이름을 금지한다. 그 금지가 ADR-0011 의 핵심이다:
 *       방이 가족을 모르기 때문에 산책 크루·병원 상담방이 같은 코드로 붙는다.</li>
 *   <li><b>위에 응용 서비스를 하나 더 둔다</b> — 둘 다 서로를 모르게 되지만, 그러면
 *       <b>"방 없는 그룹" 을 만드는 문이 열린 채 남는다.</b> {@code FamilyGroupService.create}
 *       를 직접 부르면 그만이다. 완료 조건 7 이 막으려는 상태가 정확히 그것이다.</li>
 *   <li><b>group 이 chat 을 부른다</b> ← 골랐다. {@code family_group} 행을 INSERT 하는 코드가
 *       저장소 전체에 이 메서드 하나뿐이고, 그 메서드가 같은 트랜잭션에서 방과 OWNER 를
 *       만든다. <b>문이 하나면 그 문에서만 지키면 된다.</b></li>
 * </ol>
 *
 * <p>고른 방향을 말로만 두지 않는다. {@code ChatBoundaryArchitectureTest} 가 두 가지를 잠근다 —
 * ① chat 은 여전히 밖을 이름으로 부르지 못하고, ② 밖(여기)은 chat 을 부르되
 * {@code chat.entity}·{@code chat.repository} 는 부르지 못한다. 즉 이 모듈이 아는 것은
 * {@link ChatRoomService} 와 값 레코드뿐이고, 방을 어떻게 저장하는지는 끝까지 모른다.
 *
 * <h2>"내 그룹" 을 이 표에서 못 찾는 이유</h2>
 * <p>{@code family_group} 에는 사용자 컬럼이 없다. 멤버십 표가 {@code chat_room_member} 하나이기
 * 때문이다(ADR-0011 결정 1). 그래서 {@link #findMyGroup} 은 chat 에게 "내가 살아 있는 멤버인
 * {@code FAMILY} 방들" 을 묻고 {@code originRef} 로 그룹 행을 되찾는다.
 */
@Service
@RequiredArgsConstructor
public class FamilyGroupService {

    /**
     * 이 도메인이 방에 자기를 밝히는 이름. {@code chat_room.origin_kind} 에 그대로 들어간다.
     *
     * <p>chat 은 이 문자열을 <b>해석하지 않는다.</b> {@code originKind.equals("FAMILY")} 로
     * 갈라져 이 패키지를 부르는 코드가 chat 에 생기는 순간 ADR-0011 이 사라진다.
     */
    public static final String ORIGIN_KIND = "FAMILY";

    /** 화면이 방 종류를 표시할 때 쓰는 이름표. 앱의 {@code kChatRooms} 가 쓰는 값과 같다. */
    static final String ROOM_TAG = "가족";

    /** {@code family_group.name} · {@code chat_room.name} 의 컬럼 길이. 둘은 같아야 한다. */
    private static final int MAX_NAME_LENGTH = 50;

    /**
     * 탈퇴한 계정의 자리 — {@code users} 행 자체가 없을 때 쓴다.
     *
     * <p>문자열을 여기 적지 않고 {@link User#UNKNOWN_DISPLAY_NAME} 을 가리키는 것이 요점이다.
     * 이름을 고르는 규칙은 {@link User#displayName()} 하나이고(이슈 #76), 여기서 문구만 따로
     * 적으면 같은 사람이 화면마다 다른 이름으로 보인다.
     */
    private static final String WITHDRAWN_MEMBER = User.UNKNOWN_DISPLAY_NAME;

    private final FamilyGroupRepository familyGroups;
    private final ChatRoomService chatRooms;
    private final UserRepository users;

    /**
     * 가족 그룹을 만든다. <b>같은 트랜잭션에서 방과 {@code OWNER} 멤버십이 함께 생긴다.</b>
     *
     * <p>{@code @Transactional} 이 이 메서드에 있고 {@link ChatRoomService#openRoom} 은 전파
     * 기본값({@code REQUIRED})이라 <b>같은 트랜잭션에 들어온다.</b> 방 생성이 실패하면 그룹
     * 행도 함께 롤백된다 — 완료 조건 7 이 요구하는 성질이 이것이다.
     *
     * <p>자기 호출이 아니다: {@code chatRooms} 는 주입받은 다른 빈이라 프록시를 지나간다.
     * 이 두 줄을 한 클래스 안의 private 메서드로 나누면 그 순간 프록시가 빠진다.
     *
     * <p><b>이 애너테이션 한 줄이 실제로 값을 한다 — 떼어 보고 확인했다.</b> 떼면
     * {@code SimpleJpaRepository.save} 가 자기 트랜잭션으로 그룹 행을 <b>커밋</b>하고, 그 뒤
     * 방 생성이 실패하면 "방 없는 가족" 이 남는다. 그 상태에서
     * {@code FamilyGroupInviteIntegrationTest.whenTheRoomCannotBeCreated_theGroupRowIsRolledBackToo}
     * 가 빨간불이다. 반대로 {@code openRoom} 을 {@code REQUIRES_NEW} 로 바꾸는 것은 지금
     * 그 테스트에 안 잡힌다 — 이유는 {@code ChatRoomService} javadoc 에 적었다.
     *
     * <h2>이미 가족이 있으면 409 다 — 두 번째 가족은 유령이었다</h2>
     * <p>예전에는 같은 계정으로 두 번 부르면 <b>둘 다 201</b> 이었다. 그런데
     * {@link #findMyGroup} 은 참여 순서로 첫 그룹 하나만 답하고, 방을 여럿 보는 화면은
     * {@code GET /api/chat/rooms}(M2.6) 라 아직 없다. 즉 <b>두 번째 그룹은 구현된 어떤
     * 읽기 경로로도 볼 수 없는 행</b>이었다 — 사용자는 그것이 생긴 줄도 지울 방법도 모른다.
     * 앱에서 이게 실제로 벌어지는 모양은 "생성 응답이 타임아웃돼서 다시 눌렀다" 이고,
     * 참여 경로는 그 상황을 멱등으로 공들여 막아 놓고 생성 경로만 비어 있었다.
     *
     * <p>판정 조건을 {@link #findMyGroup} 과 <b>같은 것</b>으로 둔다 — "지금
     * {@code GET /api/groups/me} 가 무언가를 돌려주는가". 조건이 갈리면 만들지도 못하는데
     * 조회도 404 인 계정이 생긴다.
     *
     * <p><b>남는 창을 정직하게 적는다.</b> 이건 확인-후-쓰기이고 DB 제약이 받치지 않는다
     * (📌 #86 원칙 5 의 1·2번을 쓸 자리가 없다 — 한 사람이 여러 방에 속하는 것은 정상이고,
     * "FAMILY 방에는 하나만" 을 표현하는 유니크 키가 {@code chat_room_member} 에는 없다).
     * 그래서 <b>정확히 동시에</b> 두 번 부르면 지금도 둘이 만들어질 수 있다. 막는 것은
     * 순차 재시도(=실제로 보고된 모양)와 rate limit 이다. 방을 여럿 갖는 것이 계약이 되는
     * M2.6 에서 이 제한 자체를 다시 판단한다.
     *
     * @throws ResponseStatusException 409 — 이미 가족 그룹에 속해 있으면
     */
    @Transactional
    public GroupResponse create(long ownerUserId, String requestedName) {
        String name = validName(requestedName);

        if (alreadyInAFamily(ownerUserId)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "이미 가족 그룹에 속해 있습니다.");
        }

        // saveAndFlush 로 id 를 먼저 받는다 — 그 id 가 방의 origin_ref 다.
        FamilyGroup group = familyGroups.saveAndFlush(
                FamilyGroup.builder().name(name).build());

        ChatRoomView room = chatRooms.openRoom(
                ORIGIN_KIND, String.valueOf(group.getId()), name, ROOM_TAG, ownerUserId);

        return response(group, room);
    }

    /**
     * 내가 속한 가족 그룹과 멤버 목록. 없으면 비어 있다(컨트롤러가 404 로 바꾼다).
     *
     * <p><b>둘 이상에 속해 있으면 가장 먼저 들어간 그룹이다.</b> 계약이 이 경로를 단수로
     * 선언했고({@code Group} 하나 · 없으면 404), 지금 화면도 가족방 하나를 전제한다.
     * 임의로 고르지 않고 <b>참여 순서</b>로 정한 것은 답이 요청마다 흔들리지 않게 하려는 것이다.
     * 여러 방을 함께 보는 화면은 {@code GET /api/chat/rooms}(M2.6)가 답한다 — 방이 여럿이라는
     * 것이 ADR-0011 의 출발점이고, 이 경로가 그것을 대신하지 않는다.
     */
    @Transactional(readOnly = true)
    public Optional<GroupResponse> findMyGroup(long userId) {
        for (ChatRoomView room : chatRooms.roomsOfMember(ORIGIN_KIND, userId)) {
            Optional<FamilyGroup> group = groupOf(room);
            if (group.isPresent()) {
                return Optional.of(response(group.get(), room));
            }
        }
        return Optional.empty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * {@link #findMyGroup} 이 무언가를 돌려주는가 — 생성 거절의 조건이다.
     *
     * <p>{@code roomsOfMember} 가 비어 있지 않은 것만 보지 않는다. 그룹 행이 사라진 방은
     * {@link #findMyGroup} 이 조용히 건너뛰므로, 그 방만 가진 계정은 조회가 404 다.
     * 그 계정의 생성을 409 로 막으면 만들 수도 볼 수도 없는 상태에 갇힌다.
     */
    private boolean alreadyInAFamily(long userId) {
        return chatRooms.roomsOfMember(ORIGIN_KIND, userId).stream()
                .anyMatch(room -> groupOf(room).isPresent());
    }

    /**
     * {@code origin_ref} 로 그룹 행을 되찾는다.
     *
     * <p>{@code origin_ref} 는 chat 에게 불투명 문자열이지만 <b>이 모듈에게는 자기 id 다.</b>
     * 그래서 해석은 여기서 한다. 숫자가 아니거나 행이 없으면 비어 있는 것으로 본다 —
     * chat 은 이 값의 존재를 확인하지 않으므로(그게 설계다) 그룹이 지워진 방이 남을 수 있고,
     * 그때 500 을 내는 대신 목록에서 조용히 빠지는 쪽이 맞다.
     */
    private Optional<FamilyGroup> groupOf(ChatRoomView room) {
        try {
            return familyGroups.findById(Long.valueOf(room.originRef()));
        } catch (NumberFormatException notOurs) {
            return Optional.empty();
        }
    }

    private GroupResponse response(FamilyGroup group, ChatRoomView room) {
        List<ChatMemberView> members = chatRooms.liveMembers(room.id());
        Map<Long, String> nicknames = nicknamesOf(members);

        return new GroupResponse(
                group.getId(),
                group.getName(),
                room.id(),
                members.stream()
                        .map(member -> new GroupMemberResponse(
                                member.userId(),
                                nicknames.getOrDefault(member.userId(), WITHDRAWN_MEMBER),
                                member.role(),
                                member.joinedAt()))
                        .toList(),
                group.getCreatedAt());
    }

    /**
     * 사용자 id → 화면에 쓸 이름. <b>한 번의 조회로 모은다</b> — 멤버마다 findById 를 부르면
     * 가족 하나를 보는 데 쿼리가 정원만큼 나간다.
     */
    private Map<Long, String> nicknamesOf(List<ChatMemberView> members) {
        List<Long> ids = members.stream().map(ChatMemberView::userId).toList();
        Map<Long, String> names = new LinkedHashMap<>();
        for (User user : users.findAllById(ids)) {
            names.put(user.getId(), user.displayName());
        }
        return names;
    }


    /**
     * 이름 검증. <b>메시지에 입력값을 되싣지 않는다</b> — 이 문구는 그대로 응답 본문이 된다(#6).
     *
     * <p>길이를 여기서 자르지 않고 거절하는 이유: 잘라서 저장하면 사용자가 적은 이름과 화면에
     * 뜨는 이름이 다르고, 그 차이를 아무도 설명해 주지 않는다.
     */
    private static String validName(String requested) {
        String name = requested == null ? "" : requested.strip();
        if (name.isEmpty() || name.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException(
                    "그룹 이름은 1자 이상 " + MAX_NAME_LENGTH + "자 이하여야 합니다.");
        }
        return name;
    }
}

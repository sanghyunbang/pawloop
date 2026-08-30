package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMemberRole;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomInviteRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomRepository;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;

/**
 * chat 모듈이 밖으로 내놓는 <b>유일한 문</b> — 이슈 #75, 근거 ADR-0011.
 *
 * <h2>방향 — 밖이 chat 을 부른다. chat 은 밖을 모른다</h2>
 * <p>이 클래스가 그 방향을 성립시키는 자리다. 시그니처에 나오는 것은 {@code long userId} 와
 * 불투명 문자열 쌍({@code originKind}/{@code originRef})뿐이고, {@code User}·
 * {@code FamilyGroup} 같은 남의 타입은 하나도 없다. 그래서 가족 그룹이 방을 열 수 있고
 * (그 방향은 허용된다), 방은 가족 그룹이 무엇인지 끝까지 모른다.
 *
 * <p>반대 방향은 {@code ChatBoundaryArchitectureTest} 가 물리적으로 막는다 — chat 의 main
 * 소스 어디에도 다른 도메인 패키지 이름이 있으면 빨간불이다. 그 규칙이 세서 <b>HTTP 어댑터도
 * 이 패키지에 못 들어온다</b>(인증 주체를 해석하려면 {@code OAuth.principal} 을 알아야 한다).
 * 그래서 컨트롤러는 {@code chatweb} 에 있다 — 그 패키지의 {@code package-info} 가 이유를 적었다.
 *
 * <h2>엔티티를 밖으로 내보내지 않는다</h2>
 * <p>돌려주는 것은 전부 {@code Chat*View} 레코드다. 엔티티를 주면 밖이 {@code chat.entity} 를
 * 이름으로 알게 되고, 그때부터 저장 구조를 바꿀 때마다 남의 모듈이 함께 깨진다.
 * 이것도 같은 테스트(§E)가 잠근다.
 *
 * <h2>트랜잭션</h2>
 * <p>모든 쓰기 메서드가 {@code @Transactional} 이고 전파는 기본값({@code REQUIRED})이다.
 * 그래서 {@code FamilyGroupService.create} 가 이 빈의 {@link #openRoom} 을 부르면
 * <b>같은 트랜잭션</b>에 들어온다 — 방 생성이 실패하면 그룹 행도 함께 롤백된다(완료 조건 7).
 *
 * <p><b>{@code REQUIRES_NEW} 로 바꿔도 지금은 그 테스트가 초록불이다 — 실측했다.</b>
 * 방 생성이 실패하면 예외가 {@code create} 밖으로 나가고, 그러면 바깥 트랜잭션도 어차피
 * 롤백되기 때문이다. {@code REQUIRES_NEW} 가 실제로 새는 것은 <b>openRoom 이 성공한 뒤
 * 그 트랜잭션 밖에서 무언가 실패할 때</b>이고, {@code create} 에는 아직 그 자리가 없다.
 * 잡히는 회귀는 다른 쪽이다: {@code create} 에서 {@code @Transactional} 을 떼면
 * {@code SimpleJpaRepository.save} 가 자기 트랜잭션으로 그룹 행을 커밋해 버리고,
 * 그때 "방 없는 그룹" 이 실제로 남는다(그 상태로 돌려 빨간불을 확인했다).
 * 전파를 바꾸려는 사람은 그 차이를 알고 바꿔야 한다.
 */
@Service
@RequiredArgsConstructor
public class ChatRoomService {

    /** 코드가 겹치면 다시 뽑는 횟수. 최종 방어선은 {@code UNIQUE (code)} 다. */
    private static final int CODE_ATTEMPTS = 5;

    private final ChatRoomRepository rooms;
    private final ChatRoomMemberRepository members;
    private final ChatRoomInviteRepository invites;
    private final ChatLimits limits;
    private final InviteCodeGenerator inviteCodes;

    /** 만료 경계를 벽시계 없이 테스트로 고정하기 위한 주입점. {@code ClockConfig} 가 준다. */
    private final Clock clock;

    // ─────────────────────────── 방 ───────────────────────────

    /**
     * 방 하나와 그 방의 {@code OWNER} 멤버십을 <b>같은 트랜잭션에서</b> 만든다.
     *
     * <p>둘을 나누면 "방은 있는데 방장이 없는 방" 이라는 상태가 생기고, 그 방은 초대코드를
     * 발급할 사람이 없어 영원히 아무도 못 들어온다.
     *
     * <p>같은 {@code (originKind, originRef)} 로 두 번 부르면 {@code UNIQUE} 제약이 두 번째를
     * 거부한다. 여기서 "있으면 그걸 쓰고 없으면 만든다" 를 조건문으로 두지 않는 이유는
     * {@code ChatRoomRepository} javadoc 에 있다 — 조건문은 동시 요청 둘을 함께 통과시킨다.
     *
     * @param originKind 부르는 도메인의 이름. chat 은 이 값을 해석하지 않는다
     * @param originRef  그 도메인의 id 를 문자열로. chat 은 이 값을 역참조하지 않는다
     */
    @Transactional
    public ChatRoomView openRoom(String originKind, String originRef,
                                 String name, String tag, long ownerUserId) {
        ChatRoom room = rooms.saveAndFlush(ChatRoom.builder()
                .originKind(originKind)
                .originRef(originRef)
                .name(name)
                .tag(tag)
                .build());

        members.saveAndFlush(ChatRoomMember.builder()
                .room(room)
                .userId(ownerUserId)
                .role(ChatRoomMemberRole.OWNER)
                .build());

        return viewOf(room);
    }

    /** 출처 쌍으로 방을 찾는다. 조회일 뿐 확인-후-쓰기의 근거가 아니다. */
    @Transactional(readOnly = true)
    public Optional<ChatRoomView> findRoom(String originKind, String originRef) {
        return rooms.findByOriginKindAndOriginRef(originKind, originRef).map(ChatRoomService::viewOf);
    }

    /**
     * 이 사람이 살아 있는 멤버로 있는, 같은 종류의 방들 — 참여 순서대로.
     *
     * <p>멤버십 표가 {@code chat_room_member} 하나이므로(ADR-0011 결정 1) "내가 속한 가족" 을
     * 아는 곳도 여기 하나다. 부르는 쪽은 {@code originRef} 로 자기 도메인 행을 찾는다.
     */
    @Transactional(readOnly = true)
    public List<ChatRoomView> roomsOfMember(String originKind, long userId) {
        return members.findLiveMembershipsByOriginKind(userId, originKind).stream()
                .map(member -> viewOf(member.getRoom()))
                .toList();
    }

    /** 방의 살아 있는 멤버. 강퇴된 행은 빠진다. */
    @Transactional(readOnly = true)
    public List<ChatMemberView> liveMembers(long roomId) {
        return members.findByRoomIdAndRemovedAtIsNull(roomId).stream()
                .map(ChatRoomService::viewOf)
                .toList();
    }

    // ─────────────────────────── 초대 ───────────────────────────

    /**
     * 초대코드를 발급한다. <b>{@code OWNER} 만.</b>
     *
     * <p>기본값(유효기간·사용 횟수)은 {@link ChatLimits} 가 답한다. 여기에 숫자를 적으면
     * {@code ChatLimitsTest} 가 빨간불이다 — 한도가 두 곳에 사는 것을 막는 장치다.
     *
     * @throws ResponseStatusException 403 — 멤버가 아니거나 방장이 아니면
     */
    @Transactional
    public ChatInviteView issueInvite(long roomId, long actorUserId) {
        requireOwner(roomId, actorUserId);

        ChatRoom room = rooms.findById(roomId)
                .orElseThrow(() -> new NoSuchElementException("방을 찾을 수 없습니다."));
        LocalDateTime now = LocalDateTime.now(clock);
        Duration ttl = limits.inviteTtl(actorUserId);

        ChatRoomInvite invite = invites.saveAndFlush(ChatRoomInvite.builder()
                .room(room)
                .code(unusedCode())
                .createdBy(actorUserId)
                .expiresAt(ttl == null ? null : now.plus(ttl))
                .maxUses(limits.maxInviteUses(actorUserId))
                .build());

        return viewOf(invite, roomId);
    }

    /**
     * 초대코드를 회수한다. <b>{@code OWNER} 만.</b> 행을 지우지 않고 {@code revoked_at} 을 찍는다.
     *
     * <p><b>지우면 "회수된 코드" 와 "없던 코드" 가 구별되지 않는다.</b> 앞의 것은 410
     * ({@code INVITE_REVOKED}), 뒤의 것은 404 여야 하는데 행이 사라지면 둘 다 404 가 된다.
     * 유출된 코드를 회수한 방장이 "이 링크는 이제 안 됩니다" 를 확인할 방법도 함께 사라진다.
     * (#9 의 {@code refresh_token} 이 같은 이유로 폐기를 삭제로 하지 않는다.)
     *
     * <p>이미 회수된 코드를 다시 회수해도 성공이다 — {@code revokeIfLive} 가 0 을 돌려줄 뿐
     * 최초 회수 시각을 덮어쓰지 않는다.
     *
     * @throws ResponseStatusException 403 — 멤버가 아니거나 방장이 아니면
     * @throws NoSuchElementException  404 — 이 방에 그런 코드가 없으면
     */
    @Transactional
    public void revokeInvite(long roomId, String code, long actorUserId) {
        requireOwner(roomId, actorUserId);

        ChatRoomInvite invite = invites.findByRoomIdAndCode(roomId, code)
                .orElseThrow(() -> new NoSuchElementException("초대코드를 찾을 수 없습니다."));

        invites.revokeIfLive(invite.getId(), LocalDateTime.now(clock));
    }

    /**
     * 초대코드로 방에 들어온다.
     *
     * <h2>검사 순서가 곧 계약이다</h2>
     * <p>{@code RefreshTokenService.rotate}(#9)가 "①없음 ②만료 ③재사용" 순서를 주석으로 못
     * 박은 것과 같은 자리다. 순서가 바뀌면 같은 상황에서 앱이 받는 코드가 달라지고, 앱은
     * 그 코드로 화면을 가른다.
     *
     * <ol>
     *   <li><b>없음</b> — 404. 회수된 코드와 구별된다({@link #revokeInvite} 참조).</li>
     *   <li><b>만료</b> — 410 {@code INVITE_EXPIRED}</li>
     *   <li><b>폐기</b> — 410 {@code INVITE_REVOKED}</li>
     *   <li><b>이미 멤버</b> — 200. 멤버도 {@code used_count} 도 늘지 않는다(완료 조건 5).</li>
     *   <li><b>소진</b> — 409 {@code INVITE_USES_EXHAUSTED}</li>
     *   <li><b>정원</b> — 409 {@code ROOM_MEMBER_LIMIT}</li>
     * </ol>
     *
     * <h2>왜 멱등이 소진·정원보다 앞인가</h2>
     * <p>이슈가 정한 순서는 <b>만료·폐기·소진·정원</b>이고 그 넷의 상대 순서는 그대로다.
     * 멱등 단락이 폐기와 소진 사이에 있는 이유는, <b>소진과 정원은 "자리를 하나 새로 쓴다" 는
     * 요청에 대한 검사</b>이기 때문이다. 이미 방에 있는 사람은 자리를 새로 쓰지 않는다 —
     * 그 사람에게 정원 초과를 이유로 409 를 주면 아무 뜻이 없다. 반대로 만료·폐기는 코드
     * 자체의 상태라 누가 물어도 답이 같아야 한다: 회수한 코드는 <b>이미 들어와 있던 사람에게도</b>
     * 즉시 410 이고, 그래도 그 사람의 멤버십은 그대로다(완료 조건 2).
     *
     * <h2>동시성</h2>
     * <p>세 가지가 전부 DB 로 판정된다(📌 #86 원칙 5).
     * <ul>
     *   <li><b>중복 참여</b> — {@code UNIQUE (room_id, user_id)}. 같은 사람이 동시에 두 번
     *       들어와도 행은 하나다.</li>
     *   <li><b>사용 횟수</b> — {@code consumeOneUse} 의 <b>영향 행 수</b>. 0 이면 진 것이고,
     *       무엇에 졌는지는 다시 읽어 판정한다.</li>
     *   <li><b>정원</b> — {@code insertMemberIfRoomHasSpace} 의 <b>영향 행 수</b>. 세는 문장과
     *       넣는 문장을 하나로 합쳤다. 보증 범위는 그 메서드의 javadoc 에 정확히 적혀 있다.</li>
     * </ul>
     * <p>실패하면 예외가 트랜잭션을 통째로 되돌리므로 <b>못 들어온 요청은 사용 횟수를 쓰지 않는다.</b>
     */
    @Transactional
    public ChatJoinResult joinByInviteCode(String code, long userId) {
        LocalDateTime now = LocalDateTime.now(clock);

        // ① 없음 — 404. 여기서 코드 값을 메시지에 싣지 않는다(#6).
        ChatRoomInvite invite = invites.findByCode(code)
                .orElseThrow(() -> new NoSuchElementException("초대코드를 찾을 수 없습니다."));

        // 아래 쓰기들이 영속성 컨텍스트를 비우므로 방의 값은 먼저 읽어 둔다.
        ChatRoomView room = viewOf(invite.getRoom());
        long roomId = room.id();

        // ② 만료 ③ 폐기 — 코드 자체의 상태다.
        ChatErrorCode dead = deadStateOf(invite, now);
        if (dead == ChatErrorCode.INVITE_EXPIRED || dead == ChatErrorCode.INVITE_REVOKED) {
            throw new ChatLimitViolationException(dead);
        }

        Optional<ChatRoomMember> existing = members.findByRoomIdAndUserId(roomId, userId);

        // ④ 이미 멤버 — 아무것도 바꾸지 않고 200.
        if (existing.isPresent() && existing.get().getRemovedAt() == null) {
            return new ChatJoinResult(room, true);
        }
        // 강퇴 = 재입장 금지(ADR-0011 결정 6). 푸는 것은 방장이고 그건 M2.7 이다.
        if (existing.isPresent() && existing.get().isRejoinBlocked()) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "이 방에는 다시 들어올 수 없습니다.");
        }

        // ⑤ 소진 — 조건부 UPDATE 의 영향 행 수가 판정이다.
        if (invites.consumeOneUse(invite.getId(), now) == 0) {
            throw new ChatLimitViolationException(recheckDeadState(invite.getId(), now));
        }

        // ⑥ 정원 — 새 행이든 되살리는 행이든 자리를 하나 쓴다.
        int capacity = limits.maxMembersPerRoom(userId);
        int seated = existing.isPresent()
                ? reviveWithinCapacity(existing.get().getId(), roomId, capacity)
                : members.insertMemberIfRoomHasSpace(roomId, userId, now, capacity);
        if (seated == 0) {
            throw new ChatLimitViolationException(ChatErrorCode.ROOM_MEMBER_LIMIT);
        }

        return new ChatJoinResult(room, false);
    }

    // ─────────────────────────── 인가 ───────────────────────────

    /**
     * 발급·회수는 방장만 한다 — 완료 조건 4.
     *
     * <p><b>멤버가 아닌 것도 403 이다.</b> 404 로 답하면 남의 방 id 를 훑어 "있는 방/없는 방"
     * 을 가려낼 수 있다. 방 존재 여부는 그 방 멤버에게만 의미가 있는 정보다.
     *
     * <p>{@code @PreAuthorize} 를 쓰지 않는 이유: 이 판정은 role 클레임이 아니라 <b>이 방에서의
     * 역할</b>이라 DB 를 봐야 한다. 📌 #86 원칙 4 가 지적한 대로 이 저장소에 메서드 수준
     * 인가는 아직 0건이고, 그 자리를 여기서 새로 만들지 않는다 — 서비스 경계에서 확인하고
     * 통합 테스트가 남의 방 id 로 403 이 나오는 것을 잠근다.
     */
    private void requireOwner(long roomId, long userId) {
        ChatRoomMember me = members.findByRoomIdAndUserId(roomId, userId)
                .filter(member -> member.getRemovedAt() == null)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다."));

        if (me.getRole() != ChatRoomMemberRole.OWNER) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "방장만 초대코드를 발급하거나 회수할 수 있습니다.");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 코드가 죽어 있으면 그 이유를, 살아 있으면 {@code null} 을 돌려준다.
     *
     * <p>순서가 {@link #joinByInviteCode} 의 계약 그대로다 — 만료 · 폐기 · 소진.
     * 둘 이상에 해당하는 코드(만료됐고 회수도 된)는 <b>먼저 오는 것</b>이 답이다.
     */
    private static ChatErrorCode deadStateOf(ChatRoomInvite invite, LocalDateTime now) {
        if (invite.getExpiresAt() != null && !invite.getExpiresAt().isAfter(now)) {
            return ChatErrorCode.INVITE_EXPIRED;
        }
        if (invite.getRevokedAt() != null) {
            return ChatErrorCode.INVITE_REVOKED;
        }
        if (invite.getMaxUses() != null && invite.getUsedCount() >= invite.getMaxUses()) {
            return ChatErrorCode.INVITE_USES_EXHAUSTED;
        }
        return null;
    }

    /**
     * {@code consumeOneUse} 에 진 뒤 <b>무엇에 졌는지</b>를 다시 읽어 판정한다.
     *
     * <p>0 을 받았다는 것은 읽은 뒤 쓰기 전에 코드가 죽었다는 뜻이고, 그 사이 벌어질 수 있는
     * 일은 셋이다 — 만료 시각이 지났거나, 방장이 회수했거나, 마지막 자리를 다른 요청이
     * 가져갔거나. 판정 자체를 지어내지 않고 지금 상태를 다시 읽는다.
     */
    private ChatErrorCode recheckDeadState(Long inviteId, LocalDateTime now) {
        ChatErrorCode dead = invites.findById(inviteId)
                .map(fresh -> deadStateOf(fresh, now))
                .orElse(ChatErrorCode.INVITE_REVOKED);
        // 셋 다 아닌데 졌다면 남는 설명은 "누가 마지막 자리를 가져갔다" 하나다.
        return dead == null ? ChatErrorCode.INVITE_USES_EXHAUSTED : dead;
    }

    /** 나갔던 사람의 재입장. 자리가 없으면 0 을 돌려준다 — 정원 판정은 호출부가 한다. */
    private int reviveWithinCapacity(Long memberId, long roomId, int capacity) {
        if (members.countByRoomIdAndRemovedAtIsNull(roomId) >= capacity) {
            return 0;
        }
        return members.reviveIfRemoved(memberId);
    }

    /** 겹치지 않는 코드 하나. 최종 방어선은 {@code UNIQUE (code)} 다. */
    private String unusedCode() {
        for (int attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
            String candidate = inviteCodes.next();
            if (!invites.existsByCode(candidate)) {
                return candidate;
            }
        }
        throw new IllegalStateException("초대코드를 만들지 못했습니다.");
    }

    private static ChatRoomView viewOf(ChatRoom room) {
        return new ChatRoomView(room.getId(), room.getOriginKind(), room.getOriginRef(),
                room.getName(), room.getTag(), room.getLastSeq(), room.getCreatedAt());
    }

    private static ChatMemberView viewOf(ChatRoomMember member) {
        return new ChatMemberView(member.getUserId(), member.getRole().name(),
                member.getLastReadSeq(), member.getJoinedAt());
    }

    private static ChatInviteView viewOf(ChatRoomInvite invite, long roomId) {
        return new ChatInviteView(invite.getCode(), roomId, invite.getExpiresAt(),
                invite.getMaxUses(), invite.getUsedCount(), invite.getCreatedAt());
    }
}

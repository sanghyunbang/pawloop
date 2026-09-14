package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMemberRole;
import com.heattrip.heat_trip_backend.chat.repository.ChatMessageRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomInviteRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomRepository;

import com.heattrip.heat_trip_backend.chat.metrics.ChatMetrics;
import lombok.RequiredArgsConstructor;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.Set;

/**
 * chat 모듈이 밖으로 내놓는 <b>문</b> — 이슈 #75, 근거 ADR-0011.
 *
 * <p><b>2026-08(#79) 에 문이 하나 늘었다: {@link ChatMessageSender}.</b> 예외가 아니라
 * 트랜잭션 경계 때문이다 — 재전송을 200 으로 번역하려면 {@code UNIQUE} 위반으로 롤백 표식이
 * 찍힌 트랜잭션 <b>밖</b>에서 잡아야 하는데, 같은 빈 안의 메서드를 부르면 스프링 프록시를
 * 지나가지 않아 트랜잭션이 아예 안 열린다. 자세한 이유와 고르지 않은 길들은 그 클래스의
 * javadoc 에 있다. 그 빈이 아는 것은 이 클래스뿐이고 방향은 여전히 한쪽이다.
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

    /** 본문 종류의 기본값. 이미지·시스템 메시지가 오면 값이 는다(M2.7 이후). */
    private static final String DEFAULT_CONTENT_TYPE = "text";

    /**
     * 사진 메시지(#452). 본문은 캡션이라 비어도 된다. 사진 자체는 chat 이 모른다 — 붙이고 읽는 것은
     * {@code chatweb.ChatMessages} 다(chat 은 경계 밖을 못 본다). 종류 문자열은 화이트리스트가 아니라
     * <b>이 값일 때만 빈 본문을 허용</b>하는 규칙 하나를 위해 있다.
     */
    public static final String IMAGE_CONTENT_TYPE = "image";

    /**
     * {@code chat_message.sender_name} 의 컬럼 폭. <b>한도가 아니라 스키마다</b> —
     * {@code users.nickname varchar(255)} 와 같은 값이고, 넘으면 500 대신 400 을 내려고 둔다.
     *
     * <h2>이 아래 셋이 같은 이유로 함께 있다 — 그게 원래 빠져 있었다</h2>
     * <p>이 상수만 있던 판을 실제로 돌려 봤다. {@code sender_name} 은 400 이 나오는데
     * <b>클라이언트가 실제로 보내는 셋</b>({@code body}·{@code content_type}·
     * {@code client_msg_id})은 전부 INSERT 까지 내려가
     * {@code DataIntegrityViolationException: Data too long for column …} 으로 죽었다.
     * {@code GlobalExceptionHandler} 에 그 타입의 핸들러가 없으니
     * {@code @ExceptionHandler(Exception.class)} 가 잡아 <b>500</b> 이 된다 — 계약
     * ({@code openapi.yaml} 의 {@code POST /api/chat/rooms/&#123;roomId&#125;/messages})이
     * 선언하지 않은 코드다. 앱은 "내 요청이 틀렸다" 와 "서버가 고장났다" 를 구분하지 못해
     * 재시도 루프를 돈다.
     *
     * <p>정작 방어가 걸려 있던 {@code sender_name} 은 클라이언트가 못 주는 값이다(#79 가
     * {@code User.displayName()} 으로 채운다). 방어의 방향이 반대였다.
     *
     * <p><b>{@link ChatLimits} 로 옮기지 않는다.</b> 이 넷은 한도가 아니라 컬럼 폭이고,
     * 바꾸려면 마이그레이션이 따라와야 한다 — 플랜에 따라 달라질 수 있는 값이 아니다.
     */
    private static final int SENDER_NAME_COLUMN_WIDTH = 255;

    /** {@code chat_message.content_type varchar(16)} 의 폭. */
    private static final int CONTENT_TYPE_COLUMN_WIDTH = 16;

    /** {@code chat_message.client_msg_id varchar(64)} 의 폭. */
    private static final int CLIENT_MSG_ID_COLUMN_WIDTH = 64;

    /**
     * {@code chat_message.body} 의 폭. <b>문자가 아니라 바이트다</b> — {@code TEXT} 는
     * 65,535<b>바이트</b>라 UTF-8 3바이트인 한글은 22,000자도 못 들어간다(실측으로
     * {@code Data too long for column 'body'} 를 봤다).
     */
    private static final int BODY_COLUMN_BYTES = 65_535;

    private final ChatRoomRepository rooms;
    private final ChatRoomMemberRepository members;
    private final ChatRoomInviteRepository invites;
    private final ChatMessageRepository messages;
    private final ChatLimits limits;
    private final InviteCodeGenerator inviteCodes;

    /**
     * 만료 경계를 벽시계 없이 테스트로 고정하기 위한 주입점. {@code ClockConfig} 가 준다.
     *
     * <p><b>이 시계의 존은 안 쓴다.</b> 빈이 주는 존은 {@code Asia/Seoul} 인데, 이 모듈이
     * 표에 넣는 값은 전부 UTC 다({@link ChatTime}). 그래서 {@code LocalDateTime.now(clock)}
     * 이 아니라 {@code ChatTime.nowUtc(clock)} 으로 읽는다 — 앞의 것을 쓰면 같은 표의
     * {@code created_at}(엔티티가 UTC 로 찍는다)과 {@code expires_at} 이 9시간 어긋난다.
     * 고정하는 것은 <b>순간</b>이라 {@code Clock.fixed} 는 그대로 동작한다.
     */
    private final Clock clock;

    /** 이 저장소의 첫 커스텀 메트릭 셋 (#80). 이름 규약은 그쪽 javadoc 에 있다. */
    private final ChatMetrics metrics;

    /** 메시지가 저장됐음을 알린다 — 듣는 쪽은 커밋 뒤에 받는다({@link ChatMessagePosted}). chat 은 누가 듣는지 모른다. */
    private final ApplicationEventPublisher events;

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
     * 방 이름을 고친다. <b>방장만.</b> 이슈 #417.
     *
     * <h2>왜 이 메서드가 여기 있어야 하는가</h2>
     * <p>방 이름은 <b>출처 도메인의 이름을 베낀 값</b>이다 — 가족 그룹을 만들면 그룹 이름이,
     * 크루를 만들면 크루 이름이 {@code chat_room.name} 에 들어간다. 그런데 그 이름을 고치는
     * 경로가 여기 없으면, 크루 이름을 바꾼 사람의 <b>채팅 목록에는 옛 이름이 남는다.</b>
     * 같은 모임이 화면 두 곳에서 다른 이름으로 보이고, 어느 쪽이 진짜인지 아무도 모른다.
     *
     * <p>출처 도메인이 {@code chat_room} 을 직접 UPDATE 하는 길은 막혀 있다 —
     * {@code ChatBoundaryArchitectureTest} 가 밖에서 {@code chat.entity}·{@code chat.repository}
     * 를 부르는 것을 금지한다. 그래서 표면을 하나 연다.
     *
     * <h2>{@code originKind} 를 안 본다</h2>
     * <p>보는 순간 chat 이 출처를 해석하기 시작한다(ADR-0011). 여기서 재는 것은 <b>방장인가</b>
     * 하나이고, "이 이름으로 바꿔도 되는가" 는 부르는 쪽의 질문이다.
     *
     * <h2>길이도 부르는 쪽이 잰다</h2>
     * <p>여기서 재려면 <b>컬럼 길이를 숫자로 적어야 하고</b>, chat main 소스에 그런 숫자를
     * 두는 것을 {@code ChatLimitsTest} 가 막는다 — 한도는 {@code FixedChatLimits} 한 곳에
     * 살아야 하기 때문이다(그 테스트가 실제로 이 줄을 잡았다). 그리고 길이는 애초에
     * <b>출처 도메인의 규칙</b>이다: 가족은 50자({@code FamilyGroupService.MAX_NAME_LENGTH}),
     * 크루는 30자({@code CrewService.MAX_NAME_LENGTH})이고 둘 다 컬럼보다 짧다. 그 관계는
     * {@code CrewNameFitsTheRoomColumnTest} 가 잰다 — 넘는 이름이 오면 500 이 나므로
     * "안 재도 된다" 가 아니라 "재는 자리가 여기가 아니다" 다.
     *
     * @return 바뀐 방
     * @throws ResponseStatusException 방장이 아니면 403
     */
    @Transactional
    public ChatRoomView renameRoom(long roomId, long actorUserId, String name) {
        requireOwner(roomId, actorUserId);

        String trimmed = name == null ? "" : name.strip();
        if (trimmed.isEmpty()) {
            throw new IllegalArgumentException("방 이름은 비울 수 없습니다.");
        }

        ChatRoom room = rooms.findById(roomId)
                .orElseThrow(() -> new NoSuchElementException("방을 찾을 수 없습니다."));
        room.rename(trimmed);
        return viewOf(rooms.saveAndFlush(room));
    }

    /**
     * <b>초대코드 없이</b> 방에 들어온다 — 이슈 #417. 공개 크루의 참여가 이 경로다.
     *
     * <h2>이 메서드는 문을 하나 여는 것이라, 여는 폭을 좁힌다</h2>
     * <p>{@link #joinByInviteCode} 는 "코드를 가진 사람" 이라는 <b>증거</b>를 요구한다. 여기엔
     * 그 증거가 없다. 그러니 대신 두 가지를 요구한다.
     * <ol>
     *   <li><b>{@code allowedOriginKinds} 가 필수다.</b> {@code null}·빈 집합이면 예외다 —
     *       {@link #joinByInviteCode} 에서 {@code null} 이 "제한 없음" 인 것과 <b>정반대</b>다.
     *       부르는 쪽이 자기 종류를 대야 한다. 그래야 이 표면으로 남의 도메인 방
     *       (가족방·상담방)에 들어가는 일이 구조적으로 불가능하다.</li>
     *   <li><b>HTTP 표면이 없다.</b> {@code chatweb} 에 이 메서드를 부르는 컨트롤러를 두지
     *       않는다. 부르는 곳은 출처 도메인 서비스뿐이고, "들어와도 되는가" 는 거기서 잰다
     *       (크루는 <b>공개 크루인가</b>로 답한다).</li>
     * </ol>
     *
     * <h2>격리 수준과 잠금은 {@link #joinByInviteCode} 와 같다</h2>
     * <p>같은 표에 같은 방식으로 INSERT 하므로 같은 데드락을 만들 수 있다. 방을 먼저 잠그고
     * ({@code chat_room → chat_room_member} 순서), {@code READ_COMMITTED} 로 내 차례의 최신을
     * 읽는다. <b>부르는 쪽이 트랜잭션을 먼저 열었다면 그쪽 격리 수준이 이긴다</b> —
     * 그래서 부르는 쪽도 {@code READ_COMMITTED} 로 열어야 하고, 크루가 그렇게 한다.
     *
     * <p>강퇴당한 사람은 못 들어온다(ADR-0011 결정 6). 공개 크루라도 마찬가지다 — 공개는
     * "누구나 들어올 수 있다" 이지 "내보낸 사람도 돌아온다" 가 아니다.
     *
     * @param allowedOriginKinds 허용할 {@code origin_kind} 들. <b>비어 있으면 안 된다</b>
     * @throws ResponseStatusException 방 종류가 다르거나(403) 재입장 금지면(403)
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ChatJoinResult joinRoom(long roomId, long userId, Set<String> allowedOriginKinds) {
        if (allowedOriginKinds == null || allowedOriginKinds.isEmpty()) {
            throw new IllegalArgumentException(
                    "코드 없이 들어오는 경로는 방 종류를 반드시 밝혀야 합니다.");
        }

        // ★ 직렬화 지점. joinByInviteCode 와 같은 순서로 잠근다.
        ChatRoom lockedRoom = rooms.lockForMemberChange(roomId)
                .orElseThrow(() -> new NoSuchElementException("방을 찾을 수 없습니다."));
        ChatRoomView room = viewOf(lockedRoom);

        if (!allowedOriginKinds.contains(room.originKind())) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "이 방에는 참여할 수 없습니다.");
        }

        Optional<ChatRoomMember> existing = members.findByRoomIdAndUserId(roomId, userId);

        if (existing.isPresent() && existing.get().getRemovedAt() == null) {
            return new ChatJoinResult(room, true);
        }
        if (existing.isPresent() && existing.get().isRejoinBlocked()) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "이 방에는 다시 들어올 수 없습니다.");
        }

        int capacity = limits.maxMembersPerRoom(userId);
        if (existing.isPresent()) {
            return reviveWithinCapacity(existing.get().getId(), roomId, capacity, room);
        }
        if (members.insertMemberIfRoomHasSpace(
                roomId, userId, ChatTime.nowUtc(clock), capacity) == 0) {
            throw new ChatLimitViolationException(ChatErrorCode.ROOM_MEMBER_LIMIT);
        }

        return new ChatJoinResult(room, false);
    }

    /**
     * <b>스스로 나간다.</b> 강퇴({@link #removeMember})와 다른 동작이다 — 이슈 #417.
     *
     * <p>차이는 하나이고 그 하나가 전부다 — <b>재입장 금지를 안 건다.</b> 나갔다가 마음이
     * 바뀌면 다시 들어올 수 있어야 한다. {@code ChatRoomMemberRepository#leave} javadoc 이
     * 둘을 한 메서드로 묶으면 안 되는 이유를 적었다.
     *
     * <p>{@code ChatMemberController} 가 "나가기는 이 이슈의 범위가 아니다" 라고 적어 둔
     * 자리다. 크루가 그것을 필요로 해서 여기서 채운다 — 다만 <b>HTTP 표면은 아직 크루 쪽에만
     * 연다.</b> {@code DELETE /api/chat/rooms/{roomId}/members/me} 는 계약에 선언만 돼 있고,
     * 그 경로를 여는 것은 방을 나간 사람의 가족 그룹이 어떻게 되는지를 함께 정해야 한다.
     *
     * <h2>방장은 못 나간다</h2>
     * <p>나가면 <b>방장이 없는 방</b>이 남는다. 그 방은 초대코드도 못 내고 강퇴도 못 하고
     * 이름도 못 고친다 — {@link #openRoom} 이 방과 방장을 한 문장에서 만드는 이유와 같다.
     * 방을 정리하는 것은 "나가기" 가 아니라 다른 동작이고, 아직 없다.
     *
     * @return 이번에 실제로 나갔으면 {@code true}, 이미 나가 있었으면 {@code false}
     * @throws ResponseStatusException 그 방의 멤버가 아니거나(404) 방장이면(400)
     */
    @Transactional
    public boolean leaveRoom(long roomId, long userId) {
        ChatRoomMember me = members.findByRoomIdAndUserId(roomId, userId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "이 방의 멤버가 아닙니다."));

        if (me.getRole() == ChatRoomMemberRole.OWNER) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "방장은 방을 나갈 수 없습니다.");
        }

        return members.leave(roomId, userId, ChatTime.nowUtc(clock)) == 1;
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

    /**
     * 출처 쌍 여럿의 방을 <b>한 번에</b> — 이슈 #417.
     *
     * <p>{@link #findRoom} 을 목록에서 반복해 부르면 N+1 이다
     * ({@code ChatRoomRepository#findByOriginKindAndOriginRefIn} javadoc). 이것도 조회일 뿐
     * 확인-후-쓰기의 근거가 아니다.
     *
     * @return 찾은 것만. 순서는 보장하지 않는다 — 순서는 부르는 쪽의 질문이다
     */
    @Transactional(readOnly = true)
    public List<ChatRoomView> findRooms(String originKind, Collection<String> originRefs) {
        if (originRefs == null || originRefs.isEmpty()) {
            return List.of();
        }
        return rooms.findByOriginKindAndOriginRefIn(originKind, originRefs).stream()
                .map(ChatRoomService::viewOf)
                .toList();
    }

    /**
     * 방마다 지금 몇 명인가 — <b>한 문장</b>이다. 이슈 #417.
     *
     * <p>{@link #liveMembers} 를 세려고 부르면 사람 목록을 통째로 실어 와 크기만 쓴다. 방
     * 50개짜리 목록에서는 그것이 <b>수백 행</b>이다. {@code myRooms} 가 이미 같은 문장으로
     * 세고 있었고(#79), 여기서는 그 문장을 목록 경로에 열어 준다.
     *
     * @return 살아 있는 멤버가 있는 방만 담긴다 — 없는 방은 <b>키가 아예 없다</b>.
     *         부르는 쪽이 {@code getOrDefault(id, 0)} 으로 읽어야 한다
     */
    @Transactional(readOnly = true)
    public Map<Long, Integer> liveMemberCounts(Collection<Long> roomIds) {
        if (roomIds == null || roomIds.isEmpty()) {
            return Map.of();
        }
        Map<Long, Integer> counts = new HashMap<>();
        for (Object[] row : members.countLiveMembersOfRooms(roomIds)) {
            counts.put((Long) row[0], ((Number) row[1]).intValue());
        }
        return counts;
    }

    /**
     * 이 사람이 같은 종류의 방들에서 갖는 역할 — 방 id → {@code OWNER}/{@code MEMBER}. #417.
     *
     * <p>{@link #roomsOfMember} 와 <b>같은 한 문장</b>을 쓴다. 목록 카드가 "참여" 를 그릴지
     * "들어가기" 를 그릴지, 그리고 고치기 버튼을 줄지를 이 지도 하나로 정한다 —
     * {@link #isLiveMember} 를 카드마다 부르면 그것이 N+1 이다.
     *
     * <p>키에 없으면 그 방의 멤버가 아니다.
     */
    @Transactional(readOnly = true)
    public Map<Long, String> myRolesIn(String originKind, long userId) {
        Map<Long, String> roles = new HashMap<>();
        for (ChatRoomMember member : members.findLiveMembershipsByOriginKind(userId, originKind)) {
            roles.put(member.getRoom().getId(), member.getRole().name());
        }
        return roles;
    }

    /**
     * 내가 살아 있는 멤버로 있는 <b>모든</b> 방 — 참여 순서대로. 이슈 #79 완료 조건 1.
     *
     * <h2>미읽음은 뺄셈이다. COUNT 를 돌리지 않는다</h2>
     * <p>{@code room.last_seq − member.last_read_seq}. 두 값 모두 이 조회가 이미 읽어 오는
     * 컬럼이라 <b>추가 쿼리가 0</b>이다. 미읽은 메시지를 세는 판은 방마다 COUNT 가 하나씩
     * 나가 방 20개면 쿼리가 21개이고, 그 값을 캐시하기 시작하면 읽음 표가 하나 더 생긴다
     * (ADR-0011 결정 3).
     *
     * <h2>인가가 없는 것이 맞다</h2>
     * <p>이 메서드는 방 id 를 받지 않는다 — 답의 범위 자체가 "내 멤버십" 이라 남의 방이
     * 섞여 들어올 문이 없다. 완료 조건 5 가 이 경로에서 요구하는 것은 403 이 아니라
     * <b>남의 방이 목록에 없다</b> 이고, 그것은 {@code where m.user_id = :userId and
     * m.removed_at is null} 이 지킨다.
     *
     * <h2>쿼리는 방 개수와 무관하게 셋이다</h2>
     * <p>멤버십+방(join fetch) · 방별 멤버 수(한 문장) · 방별 마지막 메시지(한 문장).
     * 마지막 메시지를 방마다 따로 찾으면 그것만으로 N+1 이라, 그 조회는 <b>{@code room_seq =
     * room.last_seq}</b> 로 한 번에 모은다({@code ChatMessageRepository#findLastMessagesOfRooms}).
     * 발신자 이름은 chat 이 모른다 — 붙이는 것은 {@code chatweb.ChatRooms} 다(ADR-0011 결정 4).
     */
    @Transactional(readOnly = true)
    public List<ChatRoomSummaryView> myRooms(long userId) {
        List<ChatRoomMember> memberships = members.findLiveMembershipsOf(userId);
        if (memberships.isEmpty()) {
            return List.of();
        }
        List<Long> roomIds = memberships.stream().map(m -> m.getRoom().getId()).toList();

        Map<Long, Integer> memberCounts = new HashMap<>();
        for (Object[] row : members.countLiveMembersOfRooms(roomIds)) {
            memberCounts.put((Long) row[0], ((Number) row[1]).intValue());
        }
        Map<Long, ChatMessageView> lastMessages = new HashMap<>();
        for (ChatMessage message : messages.findLastMessagesOfRooms(roomIds)) {
            lastMessages.put(message.getRoom().getId(), viewOf(message));
        }

        return memberships.stream().map(member -> {
            ChatRoom room = member.getRoom();
            return new ChatRoomSummaryView(
                    viewOf(room),
                    member.getRole().name(),
                    member.getLastReadSeq(),
                    // 자르지 않는다 — 이유는 ChatRoomSummaryView javadoc.
                    room.getLastSeq() - member.getLastReadSeq(),
                    memberCounts.getOrDefault(room.getId(), 0),
                    lastMessages.get(room.getId()),
                    member.getMutedAt() != null);
        }).toList();
    }

    /** 방의 살아 있는 멤버. 강퇴된 행은 빠진다. */
    @Transactional(readOnly = true)
    public List<ChatMemberView> liveMembers(long roomId) {
        return members.findByRoomIdAndRemovedAtIsNull(roomId).stream()
                .map(ChatRoomService::viewOf)
                .toList();
    }

    /**
     * 이 사람이 이 방의 <b>살아 있는 멤버</b>인가 — 밖에서 인가를 물을 때 쓰는 자리다(이슈 #76).
     *
     * <h2>왜 이 메서드가 여기 있어야 하나</h2>
     * <p>멤버십의 원본은 {@code chat_room_member} 하나다(ADR-0011 결정 1). 그래서 "이 사람이
     * 이 가족의 케어 기록을 볼 수 있는가" 도 결국 이 표에 묻는 질문이다. 그런데
     * {@code ChatBoundaryArchitectureTest §E} 가 chat 밖의 소스에서
     * {@code chat.repository}·{@code chat.entity} 를 부르는 것을 막는다 — 그 테스트의 실패
     * 메시지가 직접 이렇게 적었다: <b>"필요한 것이 지금 공개 표면에 없다면 메서드를 하나 더하는
     * 것이 맞다 — 리포지토리를 꺼내 쓰는 것이 아니라."</b> 이 메서드가 그 한 줄이다.
     *
     * <p>{@link #liveMembers} 로도 같은 답을 낼 수 있지만, 그러면 부르는 쪽이 방 전체 멤버
     * 목록을 받아 스스로 훑어야 한다 — 인가 판정이 호출부마다 한 벌씩 복사되고, 그중 하나가
     * {@code removedAt} 을 빠뜨리면 강퇴된 사람이 계속 본다. 판정을 이 안에 둔다.
     *
     * <h2>{@code .filter(removedAt == null)} 을 지우면 무엇이 빨간불인가</h2>
     * <p>{@code CareSharingIntegrationTest.aRemovedMember_seesNothingOfTheirFormerFamily}
     * <b>하나</b>다. 그 줄을 지우고 전체를 돌려 실측했다 — 521건 중 그 한 건만 죽고
     * ({@code Status expected:<403> but was:<200>}) 나머지는 전부 초록이었다.
     *
     * <p>그 테스트를 2026-08 에 <b>더했다.</b> 그 전에는 이 자리를 잠그는 테스트가 저장소에
     * 하나도 없었다 — 완료 조건 6 을 보던 테스트({@code anOutsider_...})는 <b>한 번도 멤버였던
     * 적 없는 남</b>만 봤고, 그건 이 줄이 아니라 {@code findByRoomIdAndUserId} 가 비어 있는
     * 것으로 막힌다. 나간 사람은 행이 남아 있어 검사의 종류가 다르다: <b>존재 여부가 아니라
     * {@code removedAt} 이다.</b> 강퇴 엔드포인트는 M2.6 에 오므로 그때까지 잠가 두지 않으면
     * 그 이슈가 이 경로를 이미 새는 상태로 물려받는다.
     *
     * <p><b>방이 없으면 이 메서드는 답할 수 없다.</b> 부르는 쪽이 {@link #findRoom} 으로 방을
     * 먼저 찾고, 못 찾으면 그것도 "멤버 아님" 으로 다룬다 — {@link #requireOwner} 가 없는 방을
     * 404 가 아니라 403 으로 다루는 것과 같은 이유다(방 존재 여부는 그 방 멤버에게만 의미가 있다).
     */
    @Transactional(readOnly = true)
    public boolean isLiveMember(long roomId, long userId) {
        return members.findByRoomIdAndUserId(roomId, userId)
                .filter(member -> member.getRemovedAt() == null)
                .isPresent();
    }

    // ─────────────────────────── 초대 ───────────────────────────

    /**
     * 초대코드를 발급한다. <b>{@code OWNER} 만.</b>
     *
     * <p>기본값(유효기간·사용 횟수)은 {@link ChatLimits} 가 답한다. 여기에 숫자를 적으면
     * {@code ChatLimitsTest} 가 빨간불이다 — 한도가 두 곳에 사는 것을 막는 장치다.
     *
     * <h2>재발급은 이전 코드를 회수하지 않는다 — 의도이고, 문서 셋이 반대말을 했었다</h2>
     * <p>부를 때마다 코드가 하나 더 생기고 이전 코드는 자기 TTL 동안 그대로 산다.
     * {@code revokeIfLive} 를 여기서 부르지 않는 것이 그 뜻이다.
     *
     * <p>2026-08 이전에는 {@code schema.md §14}·{@code openapi.yaml}·{@code ChatErrorCode}
     * 세 곳이 "방장이 재발급하면 이전 코드는 즉시 폐기된다" 고 적었고, {@code schema.md} 는
     * 그것을 "유출 대응의 유일한 수단" 이라고까지 적었다. <b>구현은 한 번도 그렇게 하지
     * 않았다</b> — 코드 A 발급 → 코드 B 발급 → A 로 참여가 200 이고 A 의 {@code revoked_at}
     * 은 {@code null} 이다(프로브로 확인). 그 서술을 믿고 앱에 "새 코드 발급" 을 유출 대응
     * 버튼으로 붙이면 보안 기능이 아닌 것을 보안 기능으로 광고하게 된다. 세 곳을 실측에
     * 맞췄고, {@code FamilyGroupInviteIntegrationTest} 가 이 동작을 잠근다.
     *
     * <p>일괄 회수와 방의 코드 목록 조회는 아직 없다 — 코드 문자열을 손에 들고 있지 않은
     * 방장은 그 코드를 지목할 수 없다. 그 둘은 M2.6 이다.
     *
     * @throws ResponseStatusException 403 — 멤버가 아니거나 방장이 아니면
     */
    @Transactional
    public ChatInviteView issueInvite(long roomId, long actorUserId) {
        requireOwner(roomId, actorUserId);

        ChatRoom room = rooms.findById(roomId)
                .orElseThrow(() -> new NoSuchElementException("방을 찾을 수 없습니다."));
        LocalDateTime now = ChatTime.nowUtc(clock);
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

        invites.revokeIfLive(invite.getId(), ChatTime.nowUtc(clock));
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
     * <h2>동시성 — 방 잠금 하나로 줄을 세운다</h2>
     * <p><b>예전에는 여기가 500 을 냈다.</b> 실제 스레드를 띄워 재현한 것 둘:
     * <ul>
     *   <li>같은 사람이 같은 코드로 동시에 두 번 → {@code Duplicate entry ... uq_chat_member}
     *       → 500. 12번 시도해서 12번 다 그랬다. 계약은 이 경우를 <b>멱등 200</b> 이라고
     *       선언하고, 실제로 그 사람은 방에 들어와 있는데 앱에는 서버 오류로 보였다.</li>
     *   <li>서로 다른 사람이 서로 다른 코드로 같은 방에 동시에 → InnoDB 데드락 → 500.
     *       4명이 동시에 누르면 3명이 졌다. 정원이 텅 빈 방에서도 재현됐다.</li>
     * </ul>
     * <p>원인은 하나였다 — <b>판정에 쓰는 값을 직렬화 지점보다 먼저 읽었다.</b> 멤버십을
     * {@code consumeOneUse} 앞에서 읽어 두고, 잠금에 진 쪽은 그 낡은 값("나는 멤버가 아니다")
     * 으로 INSERT 까지 내려갔다. 정원 검사의 카운트 서브쿼리는 그 INSERT 와 같은 문장 안에서
     * 같은 인덱스 범위를 훑어 데드락을 만들었다.
     *
     * <p>그래서 두 가지를 함께 한다.
     * <ol>
     *   <li><b>{@code ChatRoomRepository#lockForMemberChange} 로 방을 잠그고 시작한다.</b>
     *       이 방의 참여는 한 번에 하나만 진행한다. 락 순서는 그 메서드 javadoc 에 못 박았다
     *       (📌 #86 원칙 5).</li>
     *   <li><b>격리 수준을 {@code READ_COMMITTED} 로 낮춘다.</b> 기본값
     *       {@code REPEATABLE READ} 에서는 트랜잭션의 첫 읽기에 스냅샷이 고정돼, 잠금을
     *       기다린 뒤에 다시 읽어도 <b>기다리는 동안 커밋된 것을 보지 못한다.</b> 잠금은
     *       줄을 세울 뿐이고, 줄을 선 보람이 있으려면 내 차례에 최신을 읽어야 한다.
     *       그래서 이 메서드는 코드→방 id 만 스칼라로 읽고( {@code findRoomIdByCode} ),
     *       <b>방을 잠근 뒤에</b> 초대와 멤버십을 읽는다.</li>
     * </ol>
     *
     * <p>DB 제약은 그대로 마지막 방어선이다(원칙 5) — {@code UNIQUE (room_id, user_id)} 와
     * {@code consumeOneUse}·{@code insertMemberIfRoomHasSpace} 의 영향 행 수. 잠금이 빠지면
     * 데이터가 오염되는 것이 아니라 위의 500 이 돌아온다.
     *
     * <p>실패하면 예외가 트랜잭션을 통째로 되돌리므로 <b>못 들어온 요청은 사용 횟수를 쓰지 않는다.</b>
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ChatJoinResult joinByInviteCode(String code, long userId) {
        return joinByInviteCode(code, userId, null);
    }

    /**
     * 초대코드로 들어오되 <b>부르는 쪽이 허용한 종류의 방에만</b> — 이슈 #82 완료 조건 5.
     *
     * <h2>chat 은 {@code originKind} 를 해석하지 않는다</h2>
     * <p>{@code originKind.equals("FAMILY")} 로 갈라지는 코드가 여기 생기는 순간 ADR-0011 이
     * 사라진다({@code FamilyGroupService.ORIGIN_KIND} javadoc 이 그렇게 못 박아 뒀다).
     *
     * <p>그래서 여기가 하는 일은 <b>대조 하나</b>다 — 부르는 쪽이 문자열 목록을 주고, 이
     * 메서드는 방의 {@code origin_kind} 가 그 안에 있는지만 본다. "만 14세 미만" 도
     * "가족방" 도 여기서는 뜻이 없다. 뜻은 {@code chatweb} 이 안다.
     *
     * <h2>왜 부르는 쪽이 먼저 방을 들여다보지 않는가</h2>
     * <p>"코드로 방을 읽어서 종류를 보고, 괜찮으면 참여" 로 하면 그 사이가 열린다. 그리고
     * 방을 미리 읽어 주는 경로가 하나 생기는데, 그건 <b>코드만 있으면 방 정보를 볼 수 있는</b>
     * 새 표면이다. 판정을 <b>잠금 안</b>에 두는 편이 좁다.
     *
     * @param allowedOriginKinds 허용할 {@code origin_kind} 들. {@code null} 이면 제한 없음
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ChatJoinResult joinByInviteCode(String code, long userId,
                                           Set<String> allowedOriginKinds) {
        LocalDateTime now = ChatTime.nowUtc(clock);

        // ① 없음 — 404. 여기서 코드 값을 메시지에 싣지 않는다(#6).
        //    엔티티가 아니라 방 id 만 읽는다 — 이유는 findRoomIdByCode javadoc.
        long roomId = invites.findRoomIdByCode(code)
                .orElseThrow(() -> new NoSuchElementException("초대코드를 찾을 수 없습니다."));

        // ★ 직렬화 지점. 이 줄 아래의 읽기는 전부 "내 차례의 최신" 이다.
        ChatRoom lockedRoom = rooms.lockForMemberChange(roomId)
                .orElseThrow(() -> new NoSuchElementException("초대코드를 찾을 수 없습니다."));
        ChatRoomView room = viewOf(lockedRoom);

        // 부르는 쪽이 준 목록과의 대조. 뜻은 해석하지 않는다 — 위 javadoc 참조.
        if (allowedOriginKinds != null && !allowedOriginKinds.contains(room.originKind())) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "이 방에는 참여할 수 없습니다.");
        }

        ChatRoomInvite invite = invites.findByCode(code)
                .orElseThrow(() -> new NoSuchElementException("초대코드를 찾을 수 없습니다."));

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
        if (existing.isPresent()) {
            return reviveWithinCapacity(existing.get().getId(), roomId, capacity, room);
        }
        if (members.insertMemberIfRoomHasSpace(roomId, userId, now, capacity) == 0) {
            throw new ChatLimitViolationException(ChatErrorCode.ROOM_MEMBER_LIMIT);
        }

        return new ChatJoinResult(room, false);
    }

    /**
     * 멤버를 내보낸다. <b>{@code OWNER} 만.</b> 이슈 #82 완료 조건 4 · 10.
     *
     * <h2>지우지 않고 표시한다</h2>
     * <p>{@code DELETE FROM chat_room_member} 로 하면 <b>재입장 금지를 걸 자리가 사라진다.</b>
     * 행이 없으면 {@code rejoin_blocked} 를 어디에도 못 적고, 그 사람은 유효한 초대코드 하나로
     * 그냥 돌아온다. {@code last_read_seq} 도 함께 사라져 미읽음이 처음부터 다시 쌓인다.
     *
     * <p>{@link #joinByInviteCode} 의 재입장 판정은 <b>이미 있었다.</b> 없던 것은 그 상태로
     * 만드는 쪽이고, 그래서 이 메서드가 생기기 전까지 {@code rejoin_blocked} 는 한 번도
     * {@code true} 가 된 적이 없다.
     *
     * <h2>그 사람이 쓴 메시지는 남는다</h2>
     * <p>지우면 <b>신고 근거가 사라진다.</b> 디스코드도 메시지 삭제 옵션은 kick 이 아니라
     * ban 에만 붙였다. 여기서 {@code chat_message} 를 건드리지 않는 것이 그 결정이다.
     *
     * <h2>방장은 자기를 못 내보낸다</h2>
     * <p>허용하면 <b>방장이 없는 방</b>이 생기고, 그 방은 초대코드도 못 내고 강퇴도 못 한다.
     * 방을 떠나는 것은 {@code DELETE .../members/me} 이고 그건 다른 동작이다.
     *
     * @return 이번에 실제로 내보냈으면 {@code true}, 이미 나가 있었으면 {@code false}
     * @throws ResponseStatusException 방장이 아니거나(403) 그 방에 없는 사람일 때(404)
     */
    @Transactional
    public boolean removeMember(long roomId, long actorUserId, long targetUserId) {
        requireOwner(roomId, actorUserId);

        if (actorUserId == targetUserId) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "방장은 자기를 내보낼 수 없습니다.");
        }

        // 없는 사람과 이미 나간 사람을 여기서 가른다. 방장이 부르는 것이라 방 존재 여부가
        // 새지 않고, 계약도 이 경로에 404 를 선언했다.
        if (members.findByRoomIdAndUserId(roomId, targetUserId).isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "이 방의 멤버가 아닙니다.");
        }

        // 0 은 오류가 아니라 "이미 나가 있다" 다. 두 번 눌러도 결과가 같다.
        return members.kick(roomId, targetUserId, actorUserId, ChatTime.nowUtc(clock)) == 1;
    }

    /**
     * 방장을 넘긴다. <b>{@code OWNER} 만.</b> 이슈 #417.
     *
     * <h2>왜 필요한가</h2>
     * <p>{@link #leaveRoom} 이 방장을 막는다 — 나가면 초대코드도 못 내고 강퇴도 못 하는 방이
     * 남기 때문이다. 그런데 넘길 길이 없으면 <b>방을 만든 사람은 영영 못 나간다.</b> 막는
     * 쪽만 만들고 푸는 쪽을 안 만들면 그 사람은 갇힌다.
     *
     * <h2>둘 다 살아 있는 멤버여야 한다</h2>
     * <p>나간 사람에게 넘기면 <b>방장이 없는 방</b>이 그대로 만들어진다 — 막으려던 상태를
     * 다른 문으로 만드는 셈이다.
     *
     * <p>자기에게 넘기는 것은 아무 일도 아니다 — 400 으로 돌려보낸다. 조용히 통과시키면
     * 화면이 "넘겼습니다" 라고 말하는데 아무것도 안 바뀐다.
     *
     * @throws ResponseStatusException 방장이 아니면 403 · 대상이 그 방에 없으면 404 ·
     *                                 자기 자신이면 400
     */
    @Transactional
    public void transferOwner(long roomId, long actorUserId, long targetUserId) {
        requireOwner(roomId, actorUserId);

        if (actorUserId == targetUserId) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "이미 방장입니다.");
        }

        ChatRoomMember target = members.findByRoomIdAndUserId(roomId, targetUserId)
                .filter(member -> member.getRemovedAt() == null)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "이 방의 멤버가 아닙니다."));
        ChatRoomMember previous = members.findByRoomIdAndUserId(roomId, actorUserId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "이 방의 멤버가 아닙니다."));

        target.changeRole(ChatRoomMemberRole.OWNER);
        previous.changeRole(ChatRoomMemberRole.MEMBER);
        members.saveAll(List.of(target, previous));
    }

    /**
     * 방을 지운다 — <b>방장이 혼자 남았을 때만.</b> 이슈 #417.
     *
     * <h2>왜 "혼자일 때만" 인가</h2>
     * <p>방을 지우면 {@code ON DELETE CASCADE} 로 <b>메시지가 함께 사라진다.</b> 남의 대화를
     * 지우는 버튼은 만들면 안 된다 — 방장이 화가 난 날 누를 수 있는 버튼이 되고, 그날
     * 사라지는 것은 다른 사람들의 기록이다.
     *
     * <p>혼자일 때는 그 문제가 없다. 그리고 그때가 <b>실제로 필요한 때</b>다: 아무도 안
     * 들어온 모임을 만든 사람이 그것을 치우고 싶은 것이다. 사람이 있으면 넘기면 된다
     * ({@link #transferOwner}).
     *
     * <p>판정을 여기 두는 이유는 <b>멤버 수를 아는 곳이 여기</b>이기 때문이다. 부르는 쪽이
     * 세어서 넘기면 세는 순간과 지우는 순간이 갈라진다.
     *
     * @throws ResponseStatusException 방장이 아니면 403 · 다른 사람이 남아 있으면 409
     */
    @Transactional
    public void deleteRoomIfSoleMember(long roomId, long actorUserId) {
        requireOwner(roomId, actorUserId);

        if (members.countByRoomIdAndRemovedAtIsNull(roomId) > 1) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "아직 다른 분이 있어요. 방장을 넘기고 나가 주세요.");
        }

        // 멤버 행을 먼저 지우고 세션을 비운다 — DB 의 CASCADE 로는 안 풀리는 문제다
        // ({@code ChatRoomMemberRepository#deleteAllOfRoom} javadoc). 메시지·초대는 세션에
        // 없으므로 방 행이 사라질 때 DB 가 함께 지운다.
        members.deleteAllOfRoom(roomId);
        rooms.findById(roomId).ifPresent(rooms::delete);
    }

    /**
     * 재입장 금지를 푼다. <b>{@code OWNER} 만.</b> (#82)
    /**
     * 재입장 금지를 푼다. <b>{@code OWNER} 만.</b> (#82)
     *
     * <p>강퇴 확인 문구가 "방 설정에서 다시 풀 수 있습니다" 라고 <b>약속한다.</b> 그 약속을
     * 지킬 자리가 여기다 — 없으면 화면이 지키지 못할 말을 하게 된다.
     *
     * <p><b>푸는 것은 금지뿐이고 멤버십은 아니다.</b> 풀어도 방에 자동으로 돌아오지 않는다.
     * 자동으로 넣으면 방장이 "금지만 풀려고" 누른 버튼이 사람을 방에 다시 넣는 버튼이 된다.
     *
     * @return 이번에 실제로 풀었으면 {@code true}, 금지 상태가 아니었으면 {@code false}
     */
    @Transactional
    public boolean allowRejoin(long roomId, long actorUserId, long targetUserId) {
        requireOwner(roomId, actorUserId);
        return members.allowRejoin(roomId, targetUserId) == 1;
    }

    // ─────────────────────────── 메시지 ───────────────────────────

    /**
     * 메시지 한 줄을 넣고 그 방의 {@code room_seq} 를 발급한다 — 이슈 #78.
     *
     * <h2>발급과 INSERT 는 하나의 트랜잭션이다</h2>
     * <p>번호를 미리 따로 받아 두고 나중에 넣으면 {@code id} 커서와 <b>똑같은 구멍</b>이
     * 생긴다 — 5번을 받은 요청이 4번을 받은 요청보다 먼저 커밋되면, 그 사이에 폴링한
     * 클라이언트가 5까지 읽고 4를 영영 못 받는다. 그래서 두 문장이 같은 트랜잭션이고,
     * 발급이 실패하거나 <b>뒤이은 검사에 걸려 롤백되면 번호도 함께 되돌아간다.</b>
     * {@code AUTO_INCREMENT} 와 갈리는 지점이 그것이고, 그래서 빈틈이 생기지 않는다
     * ({@code ChatMessageIntegrationTest.aRejectedSendBurnsNoNumber} 가 잠근다).
     *
     * <h2>검사 순서 — 발급이 곧 직렬화 지점이다</h2>
     * <ol>
     *   <li><b>입력 검증</b> — DB 를 건드리기 전에 끝낸다. 컬럼 폭도 여기서 본다
     *       ({@link #validBody} · {@link #validContentType} · {@link #validClientMsgId}).</li>
     *   <li><b>값싼 인가</b> — 살아 있는 멤버가 아니면 403. <b>낡은 값일 수 있고, 그래도
     *       된다</b> — 최종 판정은 4번이다.</li>
     *   <li><b>발급</b>({@link ChatRoomRepository#assignNextSeq}) — 이 한 문장이 방 행에
     *       배타 잠금을 걸고 커밋까지 쥔다. <b>이 줄 아래의 읽기는 전부 "내 차례의 최신"
     *       이다.</b></li>
     *   <li><b>인가(최종)</b> — 같은 검사를 잠금 <b>뒤</b>에 한 번 더. 이유는
     *       {@link #joinByInviteCode} 와 같다: 잠금을 기다리는 동안 방장이 강퇴했을 수
     *       있고, 판정에 쓰는 값을 직렬화 지점보다 먼저 읽으면 낡은 값으로 통과한다.</li>
     *   <li><b>INSERT</b> — {@code UNIQUE (room_id, room_seq)} 와
     *       {@code UNIQUE (room_id, sender_user_id, client_msg_id)} 가 마지막 방어선이다
     *       (📌 #86 원칙 5).</li>
     * </ol>
     *
     * <h2>왜 인가가 두 번인가 — 하나만 두면 둘 중 하나가 틀린다</h2>
     * <p>4번만 두면(예전 판) <b>멤버가 아닌 사람도 방 행 배타 잠금을 잡는다.</b> 그 방의
     * 정상 전송과 {@link #joinByInviteCode} 가 전부 그 뒤에 줄을 서고, 비용은 요청 한 번이다.
     * 인증만 통과하면 {@code roomId} 하나로 남의 방을 반복해서 직렬화할 수 있다는 뜻이라
     * 그대로 두지 않았다.
     *
     * <p>2번만 두면 <b>잠금 없이 읽은 값으로 판정</b>하게 된다 — #75 에서 실제로 겪은
     * 실패다(낡은 "멤버 아님" 스냅샷을 들고 잠금을 기다렸다가 그대로 INSERT 로 내려갔다).
     *
     * <p>그래서 둘 다 둔다. 2번은 <b>값싼 fail-fast</b> 라 낡은 값으로 통과시킬 수 있지만,
     * 그때는 4번이 잡고 롤백이 번호를 되돌린다 — 정확성은 4번이 지키고 2번은 비용만
     * 줄인다. 대가는 정상 전송에서 멤버십 조회가 한 번 더 나가는 것이고,
     * {@code (room_id, user_id)} UNIQUE 인덱스의 점 조회라 그 값을 지불했다.
     *
     * <p><b>없는 방은 이제 비멤버와 같은 답(403)을 받는다.</b> 2번이 먼저 걸리기 때문이다.
     * {@link #isLiveMember}·{@link #requireOwner} 가 이미 "방 존재 여부는 그 방 멤버에게만
     * 의미가 있다" 로 다루고, 계약({@code openapi.yaml})의 전송 오퍼레이션도 404 를 선언하지
     * 않는다. 아래 {@code NoSuchElementException} 은 <b>2번과 3번 사이에 방이 사라진</b>
     * 경합에만 남는 자리다.
     *
     * <h2>락 순서 — {@link ChatRoomRepository#lockForMemberChange} 의 javadoc 과 같은 표다</h2>
     * <pre>
     *   chat_room  →  chat_room_invite  →  chat_room_member  →  chat_message
     * </pre>
     * <p>이 메서드가 잡는 것은 <b>첫째와 넷째</b>다(멤버십은 잠그지 않고 읽기만 한다).
     * 참여 경로가 잡는 것은 앞의 셋이다. 둘 다 같은 방향의 <b>부분열</b>이라 순환이 없다 —
     * 그것이 {@code chat_message} 를 맨 뒤에 둔 이유다. 메시지 행은 언제나 <b>덧붙이기만</b>
     * 하고 방보다 먼저 잠글 일이 없다. 반대로 "메시지를 먼저 잠그고 방을 잠그는" 경로를
     * 하나라도 만들면 데드락이 가능해진다(#75 에서 실제로 겪었다 — 빈 방에서도 4명 중
     * 3명이 졌다).
     *
     * <p><b>이 트랜잭션 안에서 밖으로 나가는 호출을 하지 않는다.</b> 푸시 알림도 S3 도
     * 커밋 뒤다 — {@code innodb_lock_wait_timeout} 이 기본 50초라 느린 호출 하나가 그 방의
     * 전송을 전부 막는다(📌 #86 원칙 5 · schema.md §12).
     *
     * <h2>{@code senderName} 은 스냅샷이고 응답의 이름이 아니다</h2>
     * <p>chat 은 {@code users} 를 모르므로 이름을 <b>받아서</b> 저장한다. 응답에 실을 이름은
     * 부르는 쪽이 지금 {@code users} 에서 읽는다({@code chatweb.ChatMessages} 가 그 조립을
     * 하고, 해석은 {@code chatweb.ChatSenderNames} 다 · #78 완료 조건 3·4).
     * 이 값은 "그때 방 안의 사람들이 본 이름" 으로 남는다({@link ChatMessageView} javadoc).
     *
     * @param contentType {@code null}·공백이면 {@code text}. 16자를 넘으면 400. {@link #IMAGE_CONTENT_TYPE} 면
     *                    사진 메시지(#452) — 본문은 캡션이라 비어도 된다. 사진은 chat 밖에서 같은
     *                    트랜잭션에 붙는다({@link ChatMessageSender#send})
     * @param clientMsgId 재전송 멱등키. {@code null} 이면 멱등을 요구하지 않는 전송이다.
     *                    <b>같은 사람이</b> 같은 키로 두 번 보내면 두 번째는
     *                    {@code UNIQUE (room_id, sender_user_id, client_msg_id)} 가 거부한다 —
     *                    그것을 200 으로 번역하는 것은 {@link ChatMessageSender} 다. 범위에
     *                    보낸 사람이 들어 있으므로 <b>같은 방의 다른 멤버가 같은 키를 써도
     *                    서로의 말을 지우지 않는다</b>(#79). 64자를 넘으면 400
     * @throws ResponseStatusException  403 — 이 방의 살아 있는 멤버가 아니면(없는 방도 여기다)
     * @throws NoSuchElementException   404 — 값싼 인가를 통과한 뒤 발급 전에 방이 사라졌으면
     * @throws IllegalArgumentException 400 — 본문이 비었거나(사진 메시지는 예외), 이름이 없거나, 넷 중 어느 하나가
     *                                  자기 컬럼 폭을 넘으면
     */
    @Transactional(isolation = Isolation.READ_COMMITTED)
    public ChatMessageView postMessage(long roomId, long senderUserId, String senderName,
                                       String body, String contentType, String clientMsgId) {
        // ① 입력 검증 — 잠금을 잡기 전에 끝낸다.
        String name = validSenderName(senderName);
        String type = validContentType(contentType);
        String text = validBody(body, type);
        String idempotencyKey = validClientMsgId(clientMsgId);

        // ② 값싼 인가 — 잠금을 잡기 전에 명백한 비멤버를 돌려보낸다. 최종 판정은 ④다.
        if (!isLiveMember(roomId, senderUserId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다.");
        }

        // 방 종류 — 메트릭 태그 하나를 위한 추가 왕복이다. **잠금을 잡기 전에** 부른다.
        // 뒤에서 부르면 직렬화 구간이 그만큼 길어진다 (#80).
        String roomKind = rooms.findOriginKindById(roomId).orElse("unknown");
        String roomName = rooms.findNameById(roomId).orElse("");

        // ③ ★ 직렬화 지점. 발급 문장 하나가 방 행을 잠그고 카운터를 올린다.
        long assignStartedAt = System.nanoTime();
        int assigned = rooms.assignNextSeq(roomId);
        metrics.recordSeqAssign(System.nanoTime() - assignStartedAt);
        if (assigned == 0) {
            throw new NoSuchElementException("방을 찾을 수 없습니다.");
        }
        long seq = rooms.lastAssignedSeq();

        // ④ 인가 — 다시 읽는다. 이것이 최종 판정이다. 이유는 위 javadoc.
        if (!isLiveMember(roomId, senderUserId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다.");
        }

        // ⑤ INSERT. 방은 프록시로 든다 — 엔티티를 읽어 오면 그 스냅샷의 낡은 last_seq 가
        //    플러시 순서에 따라 ③을 덮어쓸 여지가 생긴다.
        ChatMessage saved = messages.saveAndFlush(ChatMessage.builder()
                .room(rooms.getReferenceById(roomId))
                .roomSeq(seq)
                .senderUserId(senderUserId)
                .senderName(name)
                .body(text)
                .contentType(type)
                .clientMsgId(idempotencyKey)
                .build());

        // 보낸 사람의 읽음 위치를 이 메시지까지 올린다(#330). 내가 방금 보낸 말이 내 방 목록에
        // 빨간 배지 1 로 뜨던 자리다. 미읽음은 last_seq − last_read_seq 뺄셈이라 발신자를
        // 빼는 길은 COUNT 가 아니라 워터마크다. 보낼 수 있다는 것은 방을 열어 두었다는 것이므로
        // 그 앞의 메시지도 읽은 것으로 친다 — 다른 채팅 앱들과 같다. GREATEST·LEAST 는
        // raiseReadWatermark 안에 있어 뒤로 가거나 방을 넘지 않는다.
        members.raiseReadWatermark(roomId, senderUserId, seq);
        metrics.messageSent(roomKind);
        // 저장 트랜잭션 안에서 알린다 — 듣는 쪽(알림, #83)은 AFTER_COMMIT 으로 받아 커밋 뒤에만 움직인다.
        events.publishEvent(new ChatMessagePosted(roomId, roomName, seq, saved.getId(), senderUserId, name,
                previewOf(type, text), saved.getCreatedAt()));
        return viewOf(saved);
    }

    /**
     * ETag 가 맞아 304 로 끝난 폴링을 "빈 폴링" 으로 센다 — 이슈 #197 (2).
     *
     * <p>컨트롤러가 {@code If-None-Match} 를 보고 서비스에 안 들어오고 304 를 내는데, 그 경로가
     * <b>가만히 있는 방의 폴링 거의 전부</b>다. 안 세면 {@code chat.poll} 의 empty 비율이 실제보다
     * 낮게 나오고, #84(소켓 전환)의 착수 기준이 그 비율이라 판단이 틀어진다. 실측(2026-09-05,
     * 에뮬레이터 1대·빈 방)에서 카운터가 0·0 인 채 요청만 쌓이는 것으로 드러났다.
     *
     * <p>메트릭 빈은 이 모듈 안에 있고 {@code chatweb} 은 서비스만 부를 수 있어서 여기 한 줄로 연다.
     */
    public void notModifiedPoll() {
        metrics.pollEmpty();
    }

    /**
     * 내가 보낸 메시지를 지운다 — 이슈 #197.
     *
     * <p><b>행은 남고 본문만 비운다.</b> 행을 지우면 그 {@code roomSeq} 가 델타 폴링에서 빠져 읽음
     * 커서가 그 번호를 못 넘는다(ADR-0011, {@code ChatEndpointsIntegrationTest} 의 톰스톤 검사).
     * 그리고 탈퇴 정책(privacy_ko.md §3)이 이미 "보낸 메시지는 받은 사람의 대화방에 남는다" 는
     * 모양을 정했다 — 삭제도 그 모양이다: 자리는 남고 내용은 사라진다. 앱은 {@code deletedAt} 을
     * 보고 "삭제된 메시지예요" 를 그린다.
     *
     * <p><b>보낸 사람만.</b> 방장도 남의 메시지는 못 지운다 — 그건 삭제가 아니라 관리이고,
     * 신고(#82)가 그 자리다. 이미 지워진 것은 그대로 204 다 — 두 번 눌러도, 재시도해도 같다.
     * 첫 삭제 시각을 덮지 않는다.
     *
     * <p>신고 사본({@code report_snapshot})은 이 삭제와 무관하게 남는다 — 신고를 지우려고
     * 메시지를 지우는 길은 없다.
     *
     * @throws ResponseStatusException 404 없는 메시지 · 403 보낸 사람이 아님
     */
    @Transactional
    public void deleteMessage(long messageId, long userId) {
        ChatMessage message = messages.findById(messageId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "메시지를 찾을 수 없습니다."));
        if (!message.getSenderUserId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "보낸 사람만 지울 수 있습니다.");
        }
        if (message.getDeletedAt() != null) {
            return;
        }
        message.setBody("");
        message.setDeletedAt(ChatTime.nowUtc(clock));
        messages.save(message);
    }

    /**
     * {@code afterSeq} 다음 메시지들 — {@code room_seq} 오름차순.
     *
     * <p>이 이슈에서는 완료 조건 3·4 를 확인하는 데 쓰고, HTTP 로 나가는 것은 #79 다.
     * 인가를 여기서 하지 않는 것도 그래서다 — 부르는 쪽이 {@link #isLiveMember} 로 묻는다.
     *
     * <p><b>삭제된 메시지를 거르지 않는다.</b> 거르면 그 {@code roomSeq} 가 클라이언트에
     * 도달하지 않아 읽음 커서가 그 번호를 넘지 못하고 미읽음 뱃지가 영원히 남는다
     * (ADR-0011 · {@link ChatMessageView} javadoc).
     */
    @Transactional(readOnly = true)
    public List<ChatMessageView> messagesAfter(long roomId, long afterSeq, int limit) {
        return messages.findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(
                        roomId, afterSeq, Limit.of(limit)).stream()
                .map(ChatRoomService::viewOf)
                .toList();
    }

    /**
     * 메시지 한 장 — 이슈 #79. <b>인가를 여기서 한다.</b>
     *
     * <h2>{@code afterSeq} 와 {@code beforeSeq} 는 둘 중 하나다</h2>
     * <p>앞의 것은 폴링 델타(이 번호 뒤), 뒤의 것은 과거 스크롤(이 번호 앞), 둘 다 없으면
     * <b>최신 한 장</b>이다. 둘을 함께 주면 400 이다 — 계약이 그렇게 선언했고, 조용히 한쪽을
     * 무시하면 앱은 자기가 보낸 값이 먹혔다고 믿는다.
     *
     * <p><b>응답의 순서는 어느 경우에도 {@code room_seq} 오름차순이다.</b> 방향에 따라 순서가
     * 갈리면 클라이언트가 어느 파라미터를 보냈는지에 따라 정렬을 달리해야 하고, 그 분기를
     * 한 번 빠뜨리면 대화가 거꾸로 그려진다. 뒤에서 읽는 것은 인덱스 때문이고
     * ({@code ChatMessageRepository#findByRoomIdAndRoomSeqLessThanOrderByRoomSeqDesc}),
     * 뒤집는 것은 여기서 한 번이다.
     *
     * <h2>{@code limit + 1} 을 읽는다</h2>
     * <p>{@code hasMore} 를 정확히 내기 위해서다. 이유는 {@link ChatMessagePageView} javadoc.
     * {@code limit} 자체의 상한은 여기가 아니라 HTTP 어댑터가 정한다 — 그 값은 계약의
     * 질의 파라미터 기본값·최댓값이지 플랜 한도가 아니다({@link ChatLimits} 와 다른 종류의 수다).
     *
     * @throws ResponseStatusException  403 — 이 방의 살아 있는 멤버가 아니면(없는 방도 여기다)
     * @throws IllegalArgumentException 400 — 두 커서를 함께 주면
     */
    @Transactional(readOnly = true)
    public ChatMessagePageView messagePage(long roomId, long userId,
                                           Long afterSeq, Long beforeSeq, int limit) {
        if (afterSeq != null && beforeSeq != null) {
            throw new IllegalArgumentException("afterSeq 와 beforeSeq 는 함께 줄 수 없습니다.");
        }
        ChatRoom room = requireLiveMembership(roomId, userId).getRoom();
        Limit probe = Limit.of(limit + 1);

        List<ChatMessage> rows;
        boolean readFromTheFront = afterSeq != null;
        if (readFromTheFront) {
            rows = new ArrayList<>(messages.findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(
                    roomId, afterSeq, probe));
        } else {
            long ceiling = beforeSeq == null ? Long.MAX_VALUE : beforeSeq;
            rows = new ArrayList<>(messages.findByRoomIdAndRoomSeqLessThanOrderByRoomSeqDesc(
                    roomId, ceiling, probe));
            Collections.reverse(rows);
        }

        boolean hasMore = rows.size() > limit;
        if (hasMore) {
            // 넘치는 한 줄은 읽은 방향의 반대쪽 끝에 있다. 앞에서부터 읽었으면 맨 뒤,
            // 뒤에서부터 읽고 뒤집었으면 맨 앞이다.
            rows = readFromTheFront
                    ? rows.subList(0, limit)
                    : rows.subList(rows.size() - limit, rows.size());
        }

        // 폴링일 때만 센다 (#80). 뒤로 읽는 것은 과거 페이지 로드라 성격이 다르고, 그것까지
        // 세면 empty 비율이 희석되어 "간격을 늘릴지" 의 근거가 사라진다.
        // 304(ETag) 로 끝나는 폴링은 여기까지 안 온다 — 그쪽은 {@link #notModifiedPoll()} 이 센다.
        if (readFromTheFront) {
            if (rows.isEmpty()) {
                metrics.pollEmpty();
            } else {
                metrics.pollHit();
            }
        }

        return new ChatMessagePageView(
                rows.stream().map(ChatRoomService::viewOf).toList(), room.getLastSeq(), hasMore);
    }

    /**
     * <b>이 사람이</b> 같은 방에 같은 멱등키로 이미 넣어 둔 메시지 — 이슈 #79 완료 조건 3.
     *
     * <p>부르는 곳은 {@link ChatMessageSender} 하나다. <b>이 조회는 판정이 아니다</b> —
     * 중복을 막는 것은 {@code UNIQUE (room_id, sender_user_id, client_msg_id)} 이고,
     * 이것은 진 쪽이 "그래서 이미 있는 그 메시지가 무엇인가" 를 답하기 위한 조회다.
     * INSERT 앞에 두어 확인-후-쓰기로 쓰면 안 되는 이유는 그 클래스의 javadoc 에 있다.
     *
     * <p>범위가 제약과 같아야 한다({@code senderUserId} 포함). 넓게 찾으면 남의 메시지를
     * "당신이 아까 보낸 그것" 이라며 돌려주고, 그 순간 부르는 사람의 말은 사라진다.
     */
    @Transactional(readOnly = true)
    public Optional<ChatMessageView> findMessageByClientMsgId(long roomId, long senderUserId,
                                                             String clientMsgId) {
        return messages.findByRoomIdAndSenderUserIdAndClientMsgId(roomId, senderUserId, clientMsgId)
                .map(ChatRoomService::viewOf);
    }

    // ─────────────────────────── 읽음 ───────────────────────────

    /**
     * 읽음 워터마크를 올린다 — 이슈 #79 완료 조건 4·7, 근거 ADR-0011 결정 3.
     *
     * <p>계산은 전부 한 문장 안에 있다
     * ({@link ChatRoomMemberRepository#raiseReadWatermark}) — {@code GREATEST} 가 뒤로 가는
     * 것을, {@code LEAST(:seq, room.last_seq)} 가 방의 끝을 넘는 것을 막는다. 자바에서
     * 읽고 비교해서 쓰면 같은 사람의 두 기기가 동시에 보낼 때 뒤에 쓴 쪽이 이긴다.
     *
     * <p>갱신 뒤에 <b>다시 읽어서</b> 돌려준다. 요청한 값을 그대로 돌려주면 잘렸는지 무시됐는지
     * 앱이 알 수 없고, 앱은 그 값으로 뱃지를 되맞춘다({@link ChatReadView}).
     *
     * @throws ResponseStatusException  403 — 이 방의 살아 있는 멤버가 아니면(없는 방도 여기다)
     * @throws IllegalArgumentException 400 — 음수를 주면
     */
    @Transactional
    public ChatReadView markRead(long roomId, long userId, long lastReadSeq) {
        if (lastReadSeq < 0) {
            throw new IllegalArgumentException("읽음 위치가 올바르지 않습니다.");
        }
        // 인가가 먼저다. 이게 없으면 남의 방에 대한 UPDATE 가 0행을 고치고 200 이 나간다 —
        // 아무것도 안 바뀌지만 "그 방이 있다/없다" 가 응답 시간과 형태로 새는 자리다.
        requireLiveMembership(roomId, userId);
        members.raiseReadWatermark(roomId, userId, lastReadSeq);

        ChatRoomMember me = requireLiveMembership(roomId, userId);
        return new ChatReadView(me.getLastReadSeq(),
                me.getRoom().getLastSeq() - me.getLastReadSeq());
    }

    // ─────────────────────────── 인가 ───────────────────────────

    /**
     * 이 방에서의 <b>내 살아 있는 멤버십</b>. 아니면 403 — 이슈 #79 완료 조건 5·6·9.
     *
     * <p>{@link #requireOwner} 와 같은 판단을 역할 없이 한다. <b>없는 방도 403 이다</b> —
     * 404 로 답하면 방 id 를 훑어 "있는 방/없는 방" 을 가려낼 수 있고, 방 존재 여부는 그 방
     * 멤버에게만 의미가 있는 정보다. 문구도 하나다: 세 경우(방 없음 · 멤버 아님 · 강퇴됨)를
     * 다른 문구로 답하면 그 차이가 곧 열거 수단이 된다(#6).
     *
     * <p><b>{@code removed_at is null} 이 조회 조건에 있다.</b> 강퇴된 사람의 행은 남아 있으므로
     * (행을 지우지 않는다 — {@link ChatRoomMember} javadoc) "행이 있는가" 로 묻는 검사는
     * 강퇴된 사람을 통과시킨다. 그 줄을 빼면
     * {@code ChatEndpointsIntegrationTest.aRemovedMemberIsForbiddenEverywhere} 가 빨간불이다.
     */
    private ChatRoomMember requireLiveMembership(long roomId, long userId) {
        return members.findLiveMembershipWithRoom(roomId, userId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다."));
    }

    /**
     * 이 방의 값 — 단, <b>내가 살아 있는 멤버일 때만</b>. 이슈 #79.
     *
     * <p>ETag({@code "{roomId}:{lastSeq}"})를 계산하려면 방 한 행이 필요하고, 그 한 행을 주기
     * 전에 인가가 끝나 있어야 한다. <b>순서가 뒤집히면 남의 방 {@code lastSeq} 를 304/200
     * 차이로 알아낼 수 있다</b> — 타이밍이 아니라 응답 자체가 오라클이 된다.
     * 그래서 인가와 방 읽기가 <b>한 조회</b>다({@code findLiveMembershipWithRoom}).
     *
     * @throws ResponseStatusException 403 — 이 방의 살아 있는 멤버가 아니면(없는 방도 여기다)
     */
    @Transactional(readOnly = true)
    public ChatRoomView roomForMember(long roomId, long userId) {
        return viewOf(requireLiveMembership(roomId, userId).getRoom());
    }

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
                    HttpStatus.FORBIDDEN, "방장만 할 수 있습니다.");
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
     *
     * <p><b>{@code Optional.map(...).orElse(...)} 로 쓰면 안 된다 — 그렇게 적혀 있었고
     * 그게 버그였다.</b> {@code deadStateOf} 는 "살아 있다" 를 {@code null} 로 답하는데
     * {@code Optional.map} 은 매퍼가 {@code null} 을 돌려주면 <b>empty 를 만든다.</b> 그래서
     * {@code orElse(INVITE_REVOKED)} 가 발동해, 아무도 회수하지 않은 코드에 대해 언제나
     * {@code INVITE_REVOKED}(410) 가 나갔고 바로 아랫줄의 {@code INVITE_USES_EXHAUSTED}
     * 분기는 <b>도달할 수 없는 죽은 코드</b>였다. {@code max_uses=1} 코드를 두 사람이 동시에
     * 쓰는 프로브에서 진 쪽이 6번 다 "회수된 초대코드입니다" 를 받았다. 앱은
     * {@code error.code} 로 화면을 가르므로 "방장이 링크를 내렸습니다" 라는 거짓 안내였다.
     *
     * <p>다시 읽은 값이 최신인 것은 이 트랜잭션이 {@code READ_COMMITTED} 이고
     * {@code consumeOneUse} 가 영속성 컨텍스트를 비우기 때문이다. {@code REPEATABLE READ}
     * 에서는 여기서도 낡은 스냅샷을 봤다 — 계측해서 확인했다({@code used=0} 인데 DB 는 1).
     *
     * <p><b>지금 {@code null} 분기가 실제로 도달하는지 — 정직하게 적는다.</b> 방 잠금과
     * 최신 읽기가 함께 들어온 뒤로는 <b>도달하지 않는다.</b> 지면 진 이유가 반드시 셋 중
     * 하나로 보이기 때문이다. 되돌려 확인했다 — 이 메서드만 옛 {@code .map(...).orElse(...)}
     * 형태로 바꾸면 테스트는 <b>전부 초록</b>이다. 그래도 고쳐 두는 이유는 두 가지다:
     * 잠금이 빠지거나 격리 수준이 되돌아가면 그 즉시 다시 도달하고(셋을 함께 되돌리면
     * {@code whenTheLastUseIsRacedFor_theLoserIsToldItIsExhausted} 가 실제로 빨간불이다),
     * 그때 나가는 답이 "회수됐습니다" 라는 거짓말이기 때문이다.
     */
    private ChatErrorCode recheckDeadState(Long inviteId, LocalDateTime now) {
        ChatRoomInvite fresh = invites.findById(inviteId).orElse(null);
        if (fresh == null) {
            // 초대 행은 지우지 않는 것이 규칙이다(revokeInvite 참조). 여기 오면 규칙이 깨진 것이고,
            // 그때 앱에 줄 수 있는 가장 정확한 답은 "이 코드는 이제 안 된다" 다.
            return ChatErrorCode.INVITE_REVOKED;
        }
        ChatErrorCode dead = deadStateOf(fresh, now);
        // 셋 다 아닌데 졌다면 남는 설명은 "누가 마지막 자리를 가져갔다" 하나다.
        return dead == null ? ChatErrorCode.INVITE_USES_EXHAUSTED : dead;
    }

    /**
     * 나갔던 사람의 재입장.
     *
     * <p><b>영향 행 수 0 을 정원 초과로 번역하지 않는다 — 그렇게 적혀 있었고 그게 버그였다.</b>
     * {@code reviveIfRemoved} 의 {@code where ... and removed_at is not null} 은 <b>이미
     * 되살아난 뒤</b>에도 0 을 돌려준다. 그 0 을 {@code ROOM_MEMBER_LIMIT} 로 옮기는 바람에,
     * 정원 50 인 방에 2명이 있는 상태에서 "방 정원이 찼습니다" 가 나갔다(재입장 동시 2회 프로브).
     * 영향 행 수 0 에 뜻이 둘이면 그건 판정이 아니다 — {@code revokeIfLive}·
     * {@code consumeOneUse} 가 세운 원칙을 여기서만 잘못 적용한 자리였다.
     *
     * <p>이제 자리 부족은 <b>정원 검사 자체</b>가 답하고, 되살리기가 0 을 돌려주면 그건
     * "다른 요청이 나를 먼저 되살렸다" 이므로 멱등 200 이다. 방 잠금을 쥔 채 읽고 오므로
     * 실제로는 도달하지 않지만, 잠금이 사라져도 답이 틀리지 않게 남겨 둔다.
     *
     * <p>정원을 세는 문장과 되살리는 문장이 둘인 것은 그대로다. {@code READ_COMMITTED}
     * 에서도 두 문장 사이는 열려 있고, 그 창을 닫는 것은 여기서는 방 잠금이다.
     *
     * <p><b>{@code alreadyBack} 이 실제로 참이 되는지 — 정직하게 적는다.</b> 방 잠금이
     * 들어온 뒤로는 되지 않는다. 뒤에 온 요청은 ④ 에서 {@code removed_at == null} 을 보고
     * 이미 단락하기 때문이다. 되돌려 확인했다 — 이 메서드만 옛 형태(0 을 무조건
     * {@code ROOM_MEMBER_LIMIT} 로)로 바꾸면 테스트는 <b>전부 초록</b>이고, 잠금·격리와
     * 함께 되돌려야 {@code rejoiningTwiceAtTheSameMomentIsNotAMemberLimit} 가 빨간불이 된다.
     * 그래도 남겨 두는 이유는 위와 같다 — 잠금이 사라지는 날 이 답이 거짓말이 되지 않도록.
     */
    private ChatJoinResult reviveWithinCapacity(Long memberId, long roomId, int capacity,
                                                ChatRoomView room) {
        if (members.countByRoomIdAndRemovedAtIsNull(roomId) >= capacity) {
            throw new ChatLimitViolationException(ChatErrorCode.ROOM_MEMBER_LIMIT);
        }
        boolean alreadyBack = members.reviveIfRemoved(memberId) == 0;
        return new ChatJoinResult(room, alreadyBack);
    }

    /**
     * 이름 검증. <b>스냅샷이라 비어 있으면 안 된다</b> — 그 자리는 나중에 채울 수 없다.
     *
     * <p>길이를 잘라서 저장하지 않고 거절하는 것은 {@code FamilyGroupService.validName} 과
     * 같은 이유다. 다만 여기서 상한은 <b>한도가 아니라 컬럼 폭</b>이다
     * ({@code chat_message.sender_name varchar(255)} = {@code users.nickname} 과 같은 폭).
     *
     * <p><b>정상 경로가 이 길이를 넘을 수 없다는 말은 틀렸다</b> — 예전 판이 그렇게 적었다.
     * {@code users.nickname} 도 같은 {@code varchar(255)} 라 보조평면 문자(이모지) 128자짜리
     * 닉네임이 DB 에 실제로 들어갈 수 있고, 그 사람의 {@code User.displayName()} 은
     * 자바 {@code length()} 로 256 이 넘는다. 그래서 세는 단위가
     * {@link #widerThanColumn} 이다 — 그렇게 안 세면 그 사람은 채팅을 한 줄도 못 보낸다
     * (이모지 200개짜리 이름으로 400 이 나오는 것을 실측했다).
     *
     * <p><b>메시지에 입력값을 되싣지 않는다</b> — 이 문구는 그대로 응답 본문이 된다(#6).
     */
    private static String validSenderName(String requested) {
        String name = requested == null ? "" : requested.strip();
        if (name.isEmpty() || widerThanColumn(name, SENDER_NAME_COLUMN_WIDTH)) {
            throw new IllegalArgumentException("보낸 사람 이름이 올바르지 않습니다.");
        }
        return name;
    }

    /**
     * 본문 검증 — <b>비어 있지 않은가</b>와 <b>컬럼에 들어가는가</b> 둘이다.
     *
     * <p>예전 판은 길이를 안 봤고, 그 자리에 "마지막 방어선은 {@code TEXT}(64KB) 컬럼이고
     * 요청 크기로 거절하는 자리는 엔드포인트다" 라고 적혀 있었다. <b>그 판단을 되돌린다.</b>
     * 실제로 70,000자(그리고 한글 22,000자)를 넣어 보니 컬럼은 방어선이 아니라
     * {@code Data too long for column 'body'} → <b>500</b> 이었다. 400 이어야 할 요청이
     * 500 으로 나가는 것은 앱에게 "재시도하라" 는 뜻이 된다.
     *
     * <p>엔드포인트의 요청 크기 제한(#79)은 여전히 필요하다 — 그건 <b>더 앞</b>에서 큰
     * 요청을 아예 안 읽는 장치이고, 이건 컬럼 폭에 맞추는 마지막 번역이다. 둘은 대체재가
     * 아니다.
     *
     * <p>세는 단위가 문자가 아니라 <b>UTF-8 바이트</b>인 이유는 {@code TEXT} 가 바이트로
     * 세기 때문이다. 한글은 3바이트라 22,000자면 이미 넘는다.
     */
    private static String validBody(String requested, String contentType) {
        String text = requested == null ? "" : requested.strip();
        // 사진 메시지(#452)의 본문은 캡션이라 비어도 된다 — 빈 문자열로 저장한다(컬럼이 NOT NULL).
        if (text.isEmpty() && !IMAGE_CONTENT_TYPE.equals(contentType)) {
            throw new IllegalArgumentException("메시지 본문이 비어 있습니다.");
        }
        if (text.getBytes(StandardCharsets.UTF_8).length > BODY_COLUMN_BYTES) {
            throw new IllegalArgumentException("메시지 본문이 너무 깁니다.");
        }
        return text;
    }

    /**
     * 알림 미리보기(#83). 글자면 본문, 사진(#452)이면 캡션 — 캡션이 없으면 "사진" 이라고 말한다.
     * 그 밖의 종류는 비운다 — 알림이 "메시지를 보냈어요" 로 뭉뚱그린다({@code push.PushMessage}).
     */
    private static String previewOf(String type, String text) {
        if (DEFAULT_CONTENT_TYPE.equals(type)) {
            return text;
        }
        if (IMAGE_CONTENT_TYPE.equals(type)) {
            return text.isEmpty() ? "사진" : text;
        }
        return "";
    }

    /**
     * 본문 종류 검증. {@code null}·공백이면 {@link #DEFAULT_CONTENT_TYPE} 이다.
     *
     * <p>허용값 화이트리스트를 두지 않는다 — 값이 늘 때마다 chat 을 고치고 배포해야 하는
     * 것이 {@code enum} 을 안 쓴 이유와 같다({@code ChatMessage#contentType} javadoc).
     * 여기서 막는 것은 <b>컬럼에 안 들어가는 값</b> 하나다.
     */
    private static String validContentType(String requested) {
        if (requested == null || requested.isBlank()) {
            return DEFAULT_CONTENT_TYPE;
        }
        String type = requested.strip();
        if (widerThanColumn(type, CONTENT_TYPE_COLUMN_WIDTH)) {
            throw new IllegalArgumentException("메시지 종류가 올바르지 않습니다.");
        }
        return type;
    }

    /**
     * 멱등키 검증. {@code null}·공백이면 <b>{@code null}</b> — 멱등을 요구하지 않는 전송이다.
     *
     * <p>공백을 지우지 않는다. 키를 다듬으면 클라이언트가 보낸 것과 서버가 저장한 것이
     * 달라지고, 그러면 {@code UNIQUE (room_id, sender_user_id, client_msg_id)} 가 무엇을
     * 같다고 보는지가 조용히 바뀐다. 여기서 하는 것은 폭 검사 하나다.
     */
    private static String validClientMsgId(String requested) {
        if (requested == null || requested.isBlank()) {
            return null;
        }
        if (widerThanColumn(requested, CLIENT_MSG_ID_COLUMN_WIDTH)) {
            throw new IllegalArgumentException("메시지 멱등키가 올바르지 않습니다.");
        }
        return requested;
    }

    /**
     * MySQL {@code varchar(n)} 이 받는 것은 <b>문자(코드포인트) n 개</b>다.
     *
     * <p>자바 {@code String.length()} 는 UTF-16 코드유닛을 센다 — 이모지 하나가 2 다.
     * 그 차이를 무시하면 컬럼에 들어가는 값을 400 으로 거절한다(반대 방향의 틀림이라
     * 500 은 안 나지만, 그 사람은 아무것도 못 보낸다).
     */
    private static boolean widerThanColumn(String value, int columnWidth) {
        return value.codePointCount(0, value.length()) > columnWidth;
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

    /**
     * 이 방의 알림을 끄거나 켠다 — 이슈 #83. 멤버십의 속성이라 여기 있다.
     *
     * @return 서버가 실제로 쓴 값
     * @throws ResponseStatusException 403 — 살아 있는 멤버가 아니면(없는 방도 여기다)
     */
    @Transactional
    public boolean setMuted(long roomId, long userId, boolean muted) {
        ChatRoomMember member = members.findByRoomIdAndUserId(roomId, userId)
                .filter(m -> m.getRemovedAt() == null)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다."));
        member.setMutedAt(muted ? ChatTime.nowUtc(clock) : null);
        return member.getMutedAt() != null;
    }

    /**
     * 이 방의 메시지를 알려야 할 사람들 — 살아 있는 멤버 중 보낸 사람과 음소거한 사람을 뺀 것 (이슈 #83).
     *
     * <p>{@link #liveMembers} 로도 낼 수 있지만 그러면 부르는 쪽이 {@code removedAt}·{@code mutedAt} 을
     * 스스로 걸러야 한다 — {@link #isLiveMember} 가 판정을 안에 두는 것과 같은 이유로 여기 둔다.
     */
    @Transactional(readOnly = true)
    public List<Long> notifiableMembers(long roomId, long exceptUserId) {
        return members.findByRoomIdAndRemovedAtIsNull(roomId).stream()
                .filter(member -> member.getMutedAt() == null)
                .map(ChatRoomMember::getUserId)
                .filter(userId -> userId != exceptUserId)
                .toList();
    }

    private static ChatMemberView viewOf(ChatRoomMember member) {
        return new ChatMemberView(member.getUserId(), member.getRole().name(),
                member.getLastReadSeq(), member.getJoinedAt(), member.getMutedAt() != null);
    }

    private static ChatMessageView viewOf(ChatMessage message) {
        return new ChatMessageView(message.getId(), message.getRoom().getId(),
                message.getRoomSeq(), message.getSenderUserId(), message.getSenderName(),
                message.getBody(), message.getContentType(), message.getClientMsgId(),
                message.getCreatedAt(), message.getDeletedAt());
    }

    private static ChatInviteView viewOf(ChatRoomInvite invite, long roomId) {
        return new ChatInviteView(invite.getCode(), roomId,
                ChatTime.toInstant(invite.getExpiresAt()),
                invite.getMaxUses(), invite.getUsedCount(),
                ChatTime.toInstant(invite.getCreatedAt()));
    }
}

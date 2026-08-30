package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMemberRole;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 조건부 쓰기 셋의 <b>영향 행 수 계약</b>을 실제 MySQL 8 로 확인한다 — 이슈 #75.
 *
 * <h2>왜 여기서만 확인되나</h2>
 * <p>"처음 1 · 두 번째 0" 은 자바 코드가 아니라 <b>DB 의 성질</b>이다. 목으로는 정의상
 * 잡히지 않고, 서비스 통합 테스트는 응답 코드만 보므로 판정이 조건문으로 바뀌어도 초록불이다.
 * {@code RefreshTokenRepositoryTest.revokeIfLive_returnsOneThenZero}(#9)가 세운 자리를 그대로
 * 따른다 — 이 계약이 깨지면 같은 초대코드로 정원을 넘겨 들어올 수 있다.
 *
 * <p>애너테이션 두 줄이 {@code ChatRoomRepositoryTest}·{@code RefreshTokenRepositoryTest} 와
 * <b>글자 그대로</b> 같다. 한 글자만 달라도 스프링 컨텍스트가 하나 더 뜬다(#21).
 * {@code replace = NONE} 이 없으면 {@code @DataJpaTest} 가 데이터소스를 임베디드 DB 로
 * 갈아치운다(#49).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ChatRoomInviteRepositoryTest extends AbstractMySqlIntegrationTest {

    private static final long OWNER_USER = 21L;
    private static final long JOINING_USER = 22L;
    private static final long SECOND_JOINING_USER = 23L;

    /** 정원을 흉내내는 값. {@code ChatLimits} 의 한도가 아니라 이 테스트의 입력이다. */
    private static final int ROOM_OF_ONE = 1;
    private static final int ROOM_OF_TWO = 2;

    @Autowired
    private ChatRoomRepository chatRoomRepository;

    @Autowired
    private ChatRoomMemberRepository chatRoomMemberRepository;

    @Autowired
    private ChatRoomInviteRepository chatRoomInviteRepository;

    // ─────────────────── consumeOneUse — 사용 횟수 ───────────────────

    @Test
    @DisplayName("상한이 1인 코드는 처음 1, 두 번째 0 을 돌려준다 — 마지막 자리는 정확히 한 요청이 가져간다")
    void consumeOneUse_returnsOneThenZero() {
        ChatRoomInvite invite = savedInvite("USES-1", withMaxUses(1));
        LocalDateTime now = LocalDateTime.now();

        assertThat(chatRoomInviteRepository.consumeOneUse(invite.getId(), now))
                .as("첫 요청이 자리를 얻는다")
                .isEqualTo(1);
        assertThat(chatRoomInviteRepository.consumeOneUse(invite.getId(), now))
                .as("""
                        이 계약이 깨지면 상한 1짜리 코드로 두 사람이 들어온다. \
                        판정을 자바 조건문으로 옮기면 세는 문장과 쓰는 문장 사이에 다른 요청이 들어온다 \
                        (📌 #86 원칙 5).""")
                .isZero();

        assertThat(chatRoomInviteRepository.findById(invite.getId()).orElseThrow().getUsedCount())
                .as("진 요청이 숫자를 올렸다면 상한이 무의미해진다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("상한이 없는 코드(null)는 몇 번을 써도 1 이다 — null 이 무제한이라는 뜻이 여기서 성립한다")
    void consumeOneUse_neverRefusesWhenThereIsNoCeiling() {
        ChatRoomInvite invite = savedInvite("USES-NULL", unlimited());
        LocalDateTime now = LocalDateTime.now();

        assertThat(chatRoomInviteRepository.consumeOneUse(invite.getId(), now)).isEqualTo(1);
        assertThat(chatRoomInviteRepository.consumeOneUse(invite.getId(), now))
                .as("null 을 0 으로 읽으면 기본 코드가 첫 사용에서 막힌다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("회수된 코드와 만료된 코드는 0 을 돌려준다 — 상태 검사가 UPDATE 안에 함께 있다")
    void consumeOneUse_refusesRevokedAndExpiredCodes() {
        LocalDateTime now = LocalDateTime.now();

        ChatRoomInvite revoked = savedInvite("USES-REVOKED", unlimited());
        chatRoomInviteRepository.revokeIfLive(revoked.getId(), now);
        assertThat(chatRoomInviteRepository.consumeOneUse(revoked.getId(), now))
                .as("검사를 읽는 쪽에만 두면 읽은 뒤 회수된 코드가 그대로 통과한다")
                .isZero();

        ChatRoomInvite expired = savedInvite("USES-EXPIRED", unlimited());
        expired.setExpiresAt(now.minusMinutes(1));
        chatRoomInviteRepository.saveAndFlush(expired);
        assertThat(chatRoomInviteRepository.consumeOneUse(expired.getId(), now))
                .as("만료 경계도 같은 문장 안에서 본다")
                .isZero();
    }

    // ─────────────────── revokeIfLive — 회수 ───────────────────

    @Test
    @DisplayName("회수는 처음 1, 두 번째 0 이고 최초 회수 시각을 덮어쓰지 않는다")
    void revokeIfLive_returnsOneThenZeroAndKeepsTheFirstTimestamp() {
        ChatRoomInvite invite = savedInvite("REVOKE-1", unlimited());
        LocalDateTime first = LocalDateTime.now().withNano(0);
        LocalDateTime later = first.plusMinutes(10);

        assertThat(chatRoomInviteRepository.revokeIfLive(invite.getId(), first)).isEqualTo(1);
        assertThat(chatRoomInviteRepository.revokeIfLive(invite.getId(), later)).isZero();

        assertThat(chatRoomInviteRepository.findById(invite.getId()).orElseThrow().getRevokedAt())
                .as("최초 회수 시각이 사건 기록이다. 덮어쓰면 언제 무슨 일이 있었는지 알 수 없다")
                .isEqualTo(first);
    }

    @Test
    @DisplayName("회수해도 행은 남는다 — '회수된 코드' 와 '없던 코드' 를 구별하는 근거가 이것이다")
    void revokeIfLive_keepsTheRow() {
        ChatRoomInvite invite = savedInvite("REVOKE-KEEP", unlimited());

        chatRoomInviteRepository.revokeIfLive(invite.getId(), LocalDateTime.now());

        assertThat(chatRoomInviteRepository.findByCode("REVOKE-KEEP"))
                .as("""
                        DELETE 로 바꾸면 이 단언이 빨간불이다 (완료 조건 6). \
                        행이 사라지면 410 INVITE_REVOKED 와 404 가 한 덩어리가 되고, \
                        유출된 코드를 회수한 방장이 '이 링크는 이제 안 됩니다' 를 확인할 방법도 사라진다.""")
                .isPresent();
    }

    // ─────────────────── insertMemberIfRoomHasSpace — 정원 ───────────────────

    @Test
    @DisplayName("정원이 찬 방에는 0 행이 들어간다 — 세는 문장과 넣는 문장이 하나다")
    void insertMemberIfRoomHasSpace_refusesWhenTheRoomIsFull() {
        ChatRoom room = savedRoom("301");
        chatRoomMemberRepository.saveAndFlush(owner(room));   // 방장 한 명으로 정원이 찬다
        LocalDateTime now = LocalDateTime.now();

        assertThat(chatRoomMemberRepository.insertMemberIfRoomHasSpace(
                room.getId(), JOINING_USER, now, ROOM_OF_ONE))
                .as("""
                        읽어서 세고 자바에서 판단한 뒤 넣으면 두 문장 사이에 다른 요청이 들어와 \
                        마지막 자리를 함께 가져간다 (📌 #86 원칙 5).""")
                .isZero();
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(room.getId()))
                .isEqualTo(1);
    }

    @Test
    @DisplayName("자리가 남아 있으면 1 행이 들어가고 기본값(MEMBER · last_read_seq 0)으로 앉는다")
    void insertMemberIfRoomHasSpace_seatsTheJoiner() {
        ChatRoom room = savedRoom("302");
        chatRoomMemberRepository.saveAndFlush(owner(room));

        assertThat(chatRoomMemberRepository.insertMemberIfRoomHasSpace(
                room.getId(), JOINING_USER, LocalDateTime.now(), ROOM_OF_TWO))
                .isEqualTo(1);

        ChatRoomMember seated = chatRoomMemberRepository
                .findByRoomIdAndUserId(room.getId(), JOINING_USER).orElseThrow();
        assertThat(seated.getRole()).isEqualTo(ChatRoomMemberRole.MEMBER);
        assertThat(seated.getLastReadSeq())
                .as("미읽음은 room.last_seq − 이 값이다. 네이티브 INSERT 가 이 기본값을 빠뜨리면 뺄셈이 깨진다")
                .isZero();
        assertThat(seated.isRejoinBlocked()).isFalse();
        assertThat(seated.getRemovedAt()).isNull();
    }

    @Test
    @DisplayName("강퇴된 행은 정원을 차지하지 않는다 — 나간 사람 때문에 새 사람이 못 들어오면 안 된다")
    void insertMemberIfRoomHasSpace_ignoresRemovedRows() {
        ChatRoom room = savedRoom("303");
        ChatRoomMember gone = chatRoomMemberRepository.saveAndFlush(owner(room));
        gone.setRemovedAt(LocalDateTime.now());
        chatRoomMemberRepository.saveAndFlush(gone);

        assertThat(chatRoomMemberRepository.insertMemberIfRoomHasSpace(
                room.getId(), SECOND_JOINING_USER, LocalDateTime.now(), ROOM_OF_ONE))
                .as("정원의 좌변은 살아 있는 멤버 수다")
                .isEqualTo(1);
    }

    // ─────────────────── reviveIfRemoved — 재입장 ───────────────────

    @Test
    @DisplayName("나갔던 행을 되살리면 1, 이미 살아 있는 행이면 0 이다 — 두 번 되살아나 자리를 둘 쓰지 않는다")
    void reviveIfRemoved_returnsOneThenZero() {
        ChatRoom room = savedRoom("304");
        ChatRoomMember member = chatRoomMemberRepository.saveAndFlush(
                ChatRoomMember.builder().room(room).userId(JOINING_USER).build());
        member.setRemovedAt(LocalDateTime.now());
        member.setRemovedBy(OWNER_USER);
        chatRoomMemberRepository.saveAndFlush(member);

        assertThat(chatRoomMemberRepository.reviveIfRemoved(member.getId())).isEqualTo(1);
        assertThat(chatRoomMemberRepository.reviveIfRemoved(member.getId())).isZero();

        ChatRoomMember revived = chatRoomMemberRepository.findById(member.getId()).orElseThrow();
        assertThat(revived.getRemovedAt()).isNull();
        assertThat(revived.getRemovedBy())
                .as("강퇴한 사람이 남아 있으면 '지금 나가 있다' 와 '전에 강퇴당했다' 가 섞인다")
                .isNull();
    }

    // ─────────────────── 내가 속한 방 조회 ───────────────────

    @Test
    @DisplayName("내가 살아 있는 멤버인 방만, 같은 출처 종류 안에서, 참여 순서대로 나온다")
    void findLiveMembershipsByOriginKind_filtersByKindAndAliveness() {
        ChatRoom family = savedRoom("305");
        ChatRoom crew = chatRoomRepository.saveAndFlush(ChatRoom.builder()
                .originKind("WALK_CREW").originRef("305").name("서울숲 산책 크루").tag("산책 크루").build());
        ChatRoom left = savedRoom("306");

        chatRoomMemberRepository.saveAndFlush(
                ChatRoomMember.builder().room(family).userId(JOINING_USER).build());
        chatRoomMemberRepository.saveAndFlush(
                ChatRoomMember.builder().room(crew).userId(JOINING_USER).build());
        ChatRoomMember goneRow = chatRoomMemberRepository.saveAndFlush(
                ChatRoomMember.builder().room(left).userId(JOINING_USER).build());
        goneRow.setRemovedAt(LocalDateTime.now());
        chatRoomMemberRepository.saveAndFlush(goneRow);

        assertThat(chatRoomMemberRepository.findLiveMembershipsByOriginKind(JOINING_USER, "FAMILY"))
                .as("종류를 안 거르면 산책 크루 방이 가족 그룹 조회에 섞이고, "
                        + "강퇴된 행을 안 거르면 나간 가족이 목록에 남는다")
                .extracting(member -> member.getRoom().getId())
                .containsExactly(family.getId());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ChatRoom savedRoom(String originRef) {
        return chatRoomRepository.saveAndFlush(ChatRoom.builder()
                .originKind("FAMILY").originRef(originRef).name("우리 가족").tag("가족").build());
    }

    private ChatRoomMember owner(ChatRoom room) {
        return ChatRoomMember.builder()
                .room(room).userId(OWNER_USER).role(ChatRoomMemberRole.OWNER).build();
    }

    private ChatRoomInvite savedInvite(String code, Integer maxUses) {
        ChatRoom room = savedRoom("inv-" + code);
        return chatRoomInviteRepository.saveAndFlush(ChatRoomInvite.builder()
                .room(room).code(code).createdBy(OWNER_USER).maxUses(maxUses).build());
    }

    /** {@code null} = 무제한. 이름을 붙여 두면 "0 이 무제한인가" 를 매번 안 물어도 된다. */
    private static Integer unlimited() {
        return null;
    }

    private static Integer withMaxUses(int uses) {
        return uses;
    }
}

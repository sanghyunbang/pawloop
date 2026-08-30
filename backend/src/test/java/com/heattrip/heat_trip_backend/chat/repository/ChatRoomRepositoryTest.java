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
import org.springframework.dao.DataIntegrityViolationException;

import javax.sql.DataSource;

import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 세 표의 <b>제약</b>을 실제 MySQL 8 로 확인한다 — 이슈 #74 완료 조건 2·3·4.
 *
 * <h2>여기서만 확인되는 것들이다</h2>
 * <p>{@code UNIQUE (origin_kind, origin_ref)} 도, chat 경계 밖 FK 가 0개라는 것도
 * 자바 코드가 아니라 <b>DB 의 성질</b>이다. 목으로는 정의상 잡히지 않는다.
 *
 * <p>그리고 <b>{@code SchemaDdlDriftTest} 로도 안 잡힌다.</b> 그 테스트의
 * {@code describe()} 는 {@code table_name}·{@code column_name}·{@code column_type}·
 * {@code is_nullable} 넷만 읽는다 — UNIQUE 도 FK 도 인덱스도 보지 않는다.
 * {@code ddl-auto=validate} 도 같다. 그래서 UNIQUE 를 지워도 그쪽은 초록불이고,
 * 이 파일만 빨간불이 된다.
 *
 * <p>{@code replace = NONE} 인 이유는 {@code RefreshTokenRepositoryTest} 와 같다 —
 * 없으면 {@code @DataJpaTest} 가 데이터소스를 임베디드 DB 로 갈아치운다(#49).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ChatRoomRepositoryTest extends AbstractMySqlIntegrationTest {

    private static final long OWNER_USER = 11L;
    private static final long OTHER_USER = 12L;

    @Autowired
    private ChatRoomRepository chatRoomRepository;

    @Autowired
    private ChatRoomMemberRepository chatRoomMemberRepository;

    @Autowired
    private ChatRoomInviteRepository chatRoomInviteRepository;

    @Autowired
    private DataSource dataSource;

    // ─────────────── UNIQUE (origin_kind, origin_ref) — 완료 조건 2·4 ───────────────

    @Test
    @DisplayName("같은 (origin_kind, origin_ref) 로 방을 두 번 만들면 두 번째가 제약 위반으로 실패한다")
    void sameOrigin_cannotHaveTwoRooms() {
        chatRoomRepository.saveAndFlush(room("FAMILY", "77", "우리 가족", "가족"));

        assertThatThrownBy(() ->
                chatRoomRepository.saveAndFlush(room("FAMILY", "77", "우리 가족(중복)", "가족")))
                .as("""
                        '이 그룹의 방이 이미 있나 보고 없으면 만든다' 를 애플리케이션 조건문으로 두면 \
                        두 요청이 동시에 통과한다. 그 순간 같은 가족에 방이 둘 생기고 멤버십이 갈라져, \
                        어느 방이 진짜인지 아무도 모른다.
                        막는 것은 조건문이 아니라 UNIQUE (origin_kind, origin_ref) 다 (ADR-0011 · 📌 #86 원칙 5).""")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("제약은 쌍에 걸린다 — origin_ref 가 같아도 origin_kind 가 다르면 둘 다 산다")
    void theConstraintIsOnThePairNotOnEitherColumn() {
        chatRoomRepository.saveAndFlush(room("FAMILY", "88", "우리 가족", "가족"));
        chatRoomRepository.saveAndFlush(room("WALK_CREW", "88", "서울숲 산책 크루", "산책 크루"));

        assertThat(chatRoomRepository.findByOriginKindAndOriginRef("FAMILY", "88")).isPresent();
        assertThat(chatRoomRepository.findByOriginKindAndOriginRef("WALK_CREW", "88"))
                .as("한 컬럼에만 UNIQUE 를 걸면 산책 크루 방이 가족 그룹 하나에 막힌다 — "
                        + "방을 범용으로 둔 이유가 사라진다")
                .isPresent();
    }

    @Test
    @DisplayName("새 방의 last_seq 는 0 이다 — #78 의 발급이 여기서 출발한다")
    void newRoomStartsWithSequenceZero() {
        ChatRoom saved = chatRoomRepository.saveAndFlush(room("FAMILY", "99", "우리 가족", "가족"));

        assertThat(saved.getLastSeq())
                .as("UPDATE ... SET last_seq = LAST_INSERT_ID(last_seq + 1) 의 첫 결과가 1 이어야 한다")
                .isZero();
    }

    // ─────────────── UNIQUE (room_id, user_id) ───────────────

    @Test
    @DisplayName("같은 사람을 같은 방에 두 번 넣으면 실패한다 — 멤버십 행은 방·사람당 하나다")
    void sameUserCannotJoinTheSameRoomTwice() {
        ChatRoom saved = chatRoomRepository.saveAndFlush(room("FAMILY", "101", "우리 가족", "가족"));
        chatRoomMemberRepository.saveAndFlush(member(saved, OWNER_USER, ChatRoomMemberRole.OWNER));

        assertThatThrownBy(() -> chatRoomMemberRepository.saveAndFlush(
                member(saved, OWNER_USER, ChatRoomMemberRole.MEMBER)))
                .as("행이 둘이면 강퇴·미읽음이 어느 행 이야기인지 미정이 된다. 재입장도 "
                        + "새 행이 아니라 기존 행을 되살리는 것이다")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("멤버 기본값 — role 은 MEMBER, last_read_seq 는 0, 강퇴 표시는 비어 있다")
    void memberDefaultsAreWhatTheUnreadSubtractionExpects() {
        ChatRoom saved = chatRoomRepository.saveAndFlush(room("FAMILY", "102", "우리 가족", "가족"));

        ChatRoomMember stored = chatRoomMemberRepository.saveAndFlush(
                ChatRoomMember.builder().room(saved).userId(OTHER_USER).build());

        assertThat(stored.getRole()).isEqualTo(ChatRoomMemberRole.MEMBER);
        assertThat(stored.getLastReadSeq())
                .as("미읽음은 room.last_seq − 이 값이다. null 이면 뺄셈이 성립하지 않는다")
                .isZero();
        assertThat(stored.getRemovedAt()).isNull();
        assertThat(stored.isRejoinBlocked()).isFalse();
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(saved.getId()))
                .isEqualTo(1);
    }

    // ─────────────── UNIQUE (code) ───────────────

    @Test
    @DisplayName("초대코드는 UNIQUE 다 — 폐기한 코드도 재사용하지 않는다")
    void inviteCodesAreUnique() {
        ChatRoom first = chatRoomRepository.saveAndFlush(room("FAMILY", "103", "우리 가족", "가족"));
        ChatRoom second = chatRoomRepository.saveAndFlush(room("FAMILY", "104", "옆집 가족", "가족"));
        chatRoomInviteRepository.saveAndFlush(invite(first, "SAMECODE"));

        assertThatThrownBy(() -> chatRoomInviteRepository.saveAndFlush(invite(second, "SAMECODE")))
                .as("'코드 1개 = 행 1개' 가 깨지면 findByCode 가 어느 방으로 넣을지 미정이 된다")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("초대 기본값 — 만료·상한은 비어 있고(무기한·무제한) 사용 횟수는 0 이다")
    void inviteDefaultsMeanUnlimitedUntilSomeoneSetsThem() {
        ChatRoom saved = chatRoomRepository.saveAndFlush(room("FAMILY", "105", "우리 가족", "가족"));

        ChatRoomInvite stored = chatRoomInviteRepository.saveAndFlush(invite(saved, "CODE105"));

        assertThat(stored.getExpiresAt()).as("null = 무기한. 기본값 7일은 ChatLimits 가 답한다").isNull();
        assertThat(stored.getMaxUses()).as("null = 무제한").isNull();
        assertThat(stored.getUsedCount()).isZero();
        assertThat(stored.getRevokedAt()).isNull();
    }

    // ─────────────── chat 경계 밖 FK 0개 — 완료 조건 3 ───────────────

    @Test
    @DisplayName("살아 있는 DB 에서도 chat_* 표의 FK 는 전부 chat_* 를 가리킨다")
    void inTheLiveDatabase_noChatForeignKeyLeavesTheBoundary() throws Exception {
        List<String> edges = new ArrayList<>();

        try (var connection = dataSource.getConnection();
             var statement = connection.prepareStatement("""
                     SELECT table_name, referenced_table_name, constraint_name
                     FROM information_schema.key_column_usage
                     WHERE table_schema = DATABASE()
                       AND referenced_table_name IS NOT NULL
                       AND table_name LIKE 'chat\\_%'
                     """);
             ResultSet rs = statement.executeQuery()) {
            while (rs.next()) {
                edges.add("%s → %s (%s)".formatted(
                        rs.getString(1).toLowerCase(),
                        rs.getString(2).toLowerCase(),
                        rs.getString(3)));
            }
        }

        assertThat(edges)
                .as("FK 가 하나도 없으면 이 검사는 아무것도 확인하지 않은 것이다 — "
                        + "chat_room_member·chat_room_invite → chat_room 둘은 있어야 한다")
                .hasSizeGreaterThanOrEqualTo(2);
        assertThat(edges)
                .as("""
                        엔티티에 users FK 를 다시 걸면 여기서 잡힌다. \
                        탈퇴 경로가 DB 삭제 순서에 묶이고, ON DELETE CASCADE 면 탈퇴 한 번에 \
                        남의 방 멤버십과 미읽음 기준이 사라진다 (ADR-0011 결정 4 · #9 의 refresh_token 전례).""")
                .allSatisfy(edge -> assertThat(edge).contains("→ chat_"));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static ChatRoom room(String originKind, String originRef, String name, String tag) {
        return ChatRoom.builder()
                .originKind(originKind)
                .originRef(originRef)
                .name(name)
                .tag(tag)
                .build();
    }

    private static ChatRoomMember member(ChatRoom room, long userId, ChatRoomMemberRole role) {
        return ChatRoomMember.builder().room(room).userId(userId).role(role).build();
    }

    private static ChatRoomInvite invite(ChatRoom room, String code) {
        return ChatRoomInvite.builder().room(room).code(code).createdBy(OWNER_USER).build();
    }
}

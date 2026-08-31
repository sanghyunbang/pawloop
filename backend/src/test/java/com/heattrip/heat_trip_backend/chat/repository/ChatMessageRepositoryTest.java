package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Limit;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * {@code chat_message} 의 <b>제약</b>을 실제 MySQL 8 로 확인한다 — 이슈 #78 완료 조건 5·7.
 *
 * <h2>여기서만 확인되는 것들이다</h2>
 * <p>{@code UNIQUE (room_id, room_seq)} 도
 * {@code UNIQUE (room_id, sender_user_id, client_msg_id)} 도
 * 자바 코드가 아니라 <b>DB 의 성질</b>이다. {@code SchemaDdlDriftTest} 의 {@code describe()}
 * 는 컬럼 이름·타입·널 허용 넷만 읽고, {@code ddl-auto=validate} 도 UNIQUE 를 보지 않는다 —
 * 둘 다 제약이 빠진 스키마를 초록불로 통과시킨다.
 *
 * <p><b>발급의 정확성은 여기서 안 본다.</b> 스레드 20개가 1..20 을 빠짐없이 받는가는
 * {@code ChatMessageIntegrationTest} 다. 이 파일이 보는 것은 그 발급이 틀렸을 때
 * <b>마지막으로 막아 서는 것</b>이 무엇인가다(📌 #86 원칙 5).
 *
 * <p>그래서 <b>{@code UNIQUE (room_id, room_seq)} 를 지우면 빨간불이 되는 것은 이 파일이지
 * 20스레드 테스트가 아니다</b> — 되돌려서 확인했다. 이슈 #78 의 완료 조건 5 는 그 순서를
 * 반대로 적었는데, 발급이 원자적인 한 20스레드 테스트는 제약 없이도 1..20 을 낸다.
 * 제약이 없어도 되는 것이 아니라 <b>제약이 지키는 것이 다른 회귀</b>라는 뜻이다:
 * 발급을 손대는 다음 사람이 틀렸을 때 조용히 메시지를 잃는 대신 여기서 터진다.
 *
 * <p>{@code replace = NONE} 인 이유는 {@code ChatRoomRepositoryTest} 와 같다 — 없으면
 * {@code @DataJpaTest} 가 데이터소스를 임베디드 DB 로 갈아치운다(#49).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ChatMessageRepositoryTest extends AbstractMySqlIntegrationTest {

    private static final long SENDER = 31L;

    @Autowired
    private ChatRoomRepository chatRoomRepository;

    @Autowired
    private ChatMessageRepository chatMessageRepository;

    // ─────────────── UNIQUE (room_id, room_seq) — 완료 조건 5 ───────────────

    @Test
    @DisplayName("같은 방에 같은 room_seq 를 두 번 넣으면 두 번째가 제약 위반으로 실패한다")
    void aRoomSeqCannotBeUsedTwiceInTheSameRoom() {
        ChatRoom room = room("uq-seq");
        chatMessageRepository.saveAndFlush(message(room, 1L, "먼저"));

        assertThatThrownBy(() -> chatMessageRepository.saveAndFlush(message(room, 1L, "나중")))
                .as("""
                        발급이 틀리는 순간 두 메시지가 같은 번호를 든다. 그러면 afterSeq 폴링이 \
                        둘 중 하나만 주고 나머지는 영영 도달하지 않는다 — 그때 조용히 데이터가 \
                        어긋나는 대신 여기서 터지게 하는 것이 이 제약이다 (ADR-0011 결정 2).""")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("제약은 (방, 번호) 쌍에 걸린다 — 방이 다르면 둘 다 1번을 쓴다 (완료 조건 2)")
    void everyRoomHasItsOwnNumbering() {
        ChatRoom family = room("가족");
        ChatRoom crew = room("크루");

        chatMessageRepository.saveAndFlush(message(family, 1L, "가족방 첫 줄"));
        chatMessageRepository.saveAndFlush(message(crew, 1L, "크루방 첫 줄"));

        assertThat(chatMessageRepository.count()).isGreaterThanOrEqualTo(2);
    }

    // ────── UNIQUE (room_id, sender_user_id, client_msg_id) — 재전송 멱등 ──────

    @Test
    @DisplayName("같은 사람이 같은 방에 같은 client_msg_id 로 두 번 넣으면 두 번째가 실패한다 — 재전송이 두 줄이 되지 않는다")
    void theSameClientMessageIdCannotLandTwiceInOneRoom() {
        ChatRoom room = room("uq-client");
        ChatMessage first = message(room, 1L, "지하철에서 보냄");
        first.setClientMsgId("c-1");
        chatMessageRepository.saveAndFlush(first);

        ChatMessage retry = message(room, 2L, "지하철에서 보냄");
        retry.setClientMsgId("c-1");

        assertThatThrownBy(() -> chatMessageRepository.saveAndFlush(retry))
                .as("""
                        타임아웃된 전송을 앱이 재시도하는 것은 정상 동작이다. 이 제약이 없으면 \
                        같은 말이 두 줄 남고, 둘은 서로 다른 room_seq 를 가져 어느 쪽도 지울 \
                        근거가 없다 (#79 완료 조건 3·8).""")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("같은 방의 다른 사람이 같은 client_msg_id 를 써도 둘 다 들어간다 — 멱등의 범위는 보낸 사람까지다")
    void twoMembersOfOneRoomCanUseTheSameKey() {
        ChatRoom room = room("uq-client-scope");
        ChatMessage mine = message(room, 1L, "A 의 메모");
        mine.setClientMsgId("shared");
        chatMessageRepository.saveAndFlush(mine);

        ChatMessage theirs = message(room, 2L, "B 가 하려던 말");
        theirs.setSenderUserId(SENDER + 1);
        theirs.setClientMsgId("shared");

        chatMessageRepository.saveAndFlush(theirs);

        assertThat(chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(room.getId(), 0, Limit.of(10)))
                .as("""
                        범위가 (room_id, client_msg_id) 이던 판에서는 두 번째 INSERT 가 거부됐고,                         HTTP 위에서는 그것이 'B 가 200 과 함께 A 의 메시지를 돌려받는다' 로                         나타났다 — B 가 하려던 말은 어디에도 남지 않는다 (#79).""")
                .hasSize(2);
        assertThat(chatMessageRepository
                .findByRoomIdAndSenderUserIdAndClientMsgId(room.getId(), SENDER, "shared"))
                .as("멱등 조회도 같은 범위여야 남의 메시지를 '당신이 아까 보낸 그것' 이라며 돌려주지 않는다")
                .get()
                .extracting(ChatMessage::getBody)
                .isEqualTo("A 의 메모");
    }

    @Test
    @DisplayName("client_msg_id 가 NULL 인 메시지는 서로 충돌하지 않는다 — 멱등키 없는 전송을 막지 않는다")
    void messagesWithoutAnIdempotencyKeyDoNotCollide() {
        ChatRoom room = room("null-client");

        chatMessageRepository.saveAndFlush(message(room, 1L, "첫 줄"));
        chatMessageRepository.saveAndFlush(message(room, 2L, "둘째 줄"));

        assertThat(chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(room.getId(), 0, Limit.of(10)))
                .as("""
                        MySQL 의 UNIQUE 인덱스는 NULL 을 여러 번 허용한다. 그 성질에 기대고 있으므로 \
                        여기서 확인해 둔다 — client_msg_id 를 NOT NULL 로 바꾸면 이 테스트가 먼저 깨진다.""")
                .hasSize(2);
    }

    // ─────────────── 커서는 room_seq 다 — 완료 조건 7 ───────────────

    @Test
    @DisplayName("조회 순서는 id 가 아니라 room_seq 를 따른다 — 둘이 어긋나게 넣어 확인한다")
    void readingFollowsTheRoomSeqNotTheAutoIncrementId() {
        ChatRoom room = room("cursor");

        // 먼저 들어간 행이 더 큰 번호를 갖게 한다. AUTO_INCREMENT 는 넣은 순서를 따르므로
        // id 오름차순과 room_seq 오름차순이 서로 반대가 된다.
        ChatMessage laterNumber = chatMessageRepository.saveAndFlush(message(room, 2L, "두 번째 말"));
        ChatMessage earlierNumber = chatMessageRepository.saveAndFlush(message(room, 1L, "첫 번째 말"));

        assertThat(earlierNumber.getId())
                .as("이 전제가 깨지면 이 테스트는 아무것도 구별하지 못한다")
                .isGreaterThan(laterNumber.getId());

        List<ChatMessage> read = chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(room.getId(), 0, Limit.of(10));

        assertThat(read.stream().map(ChatMessage::getBody))
                .as("""
                        id 를 커서로 되돌리면 여기가 뒤집힌다. id 는 INSERT 시점에 배정되고 \
                        가시성은 커밋 시점에 생기므로, 늦게 커밋된 작은 id 를 afterId 폴링은 \
                        영구히 건너뛴다 (ADR-0011 결정 2 · #78 완료 조건 7).""")
                .containsExactly("첫 번째 말", "두 번째 말");
    }

    @Test
    @DisplayName("afterSeq 는 그 번호를 뺀 다음부터다 — 델타 폴링이 같은 메시지를 두 번 주지 않는다")
    void afterSeqIsExclusive() {
        ChatRoom room = room("delta");
        chatMessageRepository.saveAndFlush(message(room, 1L, "하나"));
        chatMessageRepository.saveAndFlush(message(room, 2L, "둘"));
        chatMessageRepository.saveAndFlush(message(room, 3L, "셋"));

        assertThat(chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(room.getId(), 2, Limit.of(10))
                .stream().map(ChatMessage::getBody))
                .containsExactly("셋");
    }

    // ─────────────── 톰스톤 — 삭제된 메시지도 조회에 나온다 ───────────────

    @Test
    @DisplayName("deleted_at 이 찍힌 메시지도 조회에 그대로 나온다 — 거르면 미읽음 뱃지가 영원히 안 지워진다")
    void deletedMessagesComeBackAsTombstones() {
        ChatRoom room = room("tombstone");
        ChatMessage deleted = message(room, 1L, "지운 말");
        deleted.setDeletedAt(LocalDateTime.now());
        chatMessageRepository.saveAndFlush(deleted);
        chatMessageRepository.saveAndFlush(message(room, 2L, "남은 말"));

        List<ChatMessage> read = chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(room.getId(), 0, Limit.of(10));

        assertThat(read)
                .as("""
                        조회에서 빼면 그 room_seq 가 클라이언트에 도달하지 않는다. 미읽음이 \
                        room.last_seq − member.last_read_seq 뺄셈이라 읽음 커서가 그 번호를 넘지 \
                        못하고, 방을 아무리 열어도 뱃지가 안 지워진다 (ADR-0011).
                        본문을 가리는 것은 응답을 만드는 쪽의 일이지 조회에서 빼는 것이 아니다.""")
                .hasSize(2);
        assertThat(read.get(0).getDeletedAt())
                .as("톰스톤인지 아닌지는 이 값으로 가른다 — 없으면 앱이 구별할 수 없다")
                .isNotNull();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ChatRoom room(String ref) {
        return chatRoomRepository.saveAndFlush(ChatRoom.builder()
                .originKind("MSG_TEST")
                .originRef("%s-%d".formatted(ref, System.nanoTime()))
                .name("테스트 방")
                .tag("가족")
                .build());
    }

    private static ChatMessage message(ChatRoom room, long seq, String body) {
        return ChatMessage.builder()
                .room(room)
                .roomSeq(seq)
                .senderUserId(SENDER)
                .senderName("보호자")
                .body(body)
                .build();
    }
}

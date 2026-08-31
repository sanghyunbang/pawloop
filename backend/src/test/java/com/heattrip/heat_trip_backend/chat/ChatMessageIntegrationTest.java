package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.chatweb.ChatSenderNames;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 방별 {@code room_seq} 발급과 발신자 이름 해석 — 이슈 #78 완료 조건 1·2·3·4.
 *
 * <h2>스레드를 실제로 띄운다</h2>
 * <p>완료 조건 1("스레드 20개가 동시에 넣으면 1..20 이 빠짐없이 한 번씩")은 코드를 읽어서
 * 확인할 수 있는 성질이 아니다. {@code UPDATE ... SET last_seq = last_seq + 1} 뒤에 그 값을
 * 다시 <b>읽는</b> 판은 읽는 시점에 남이 또 올렸을 수 있고, JPA 로 읽어서 더해 쓰는 판은
 * 두 트랜잭션이 같은 값을 읽어 같은 번호를 쓴다. 둘 다 "코드를 보면 맞아 보인다".
 *
 * <p>실제로 그렇게 짜고 이 테스트를 돌려 봤다 — 순진한 판(읽고 더해서 쓰기)에서
 * <b>20개 중 17개가</b> {@code Duplicate entry '1-1' for key 'chat_message.uq_chat_room_seq'}
 * 로 죽었다(성공 3건). 지금 판은 {@code LAST_INSERT_ID(last_seq + 1)} 한 문장이다.
 *
 * <p><b>다만 이 테스트가 지키는 것은 UNIQUE 제약이 아니다 — 발급이다.</b> 되돌려서 확인했다:
 * {@code UNIQUE (room_id, room_seq)} 를 지우고 이 테스트를 돌리면 <b>여전히 초록불</b>이고
 * ({@code ChatMessageRepositoryTest.aRoomSeqCannotBeUsedTwiceInTheSameRoom} 만 빨간불이다),
 * 발급을 순진한 판으로 되돌리면 UNIQUE 가 그대로여도 빨간불이다. 발급이 원자적인 한
 * 제약은 <b>메커니즘이 아니라 마지막 방어선</b>이라 그렇다(📌 #86 원칙 5).
 *
 * <h2>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 의도다</h2>
 * <p>{@code SchemaDdlDriftTest} 와 <b>글자 그대로</b> 같아야 스프링 컨텍스트 캐시를
 * 공유한다(#21). {@code @AutoConfigureMockMvc}·{@code @MockBean}·
 * {@code @TestPropertySource} 를 하나라도 붙이면 캐시 키가 갈라져 컨텍스트가 한 번 더 뜬다.
 * 여기서 재는 것은 HTTP 가 아니라 <b>서비스와 실제 MySQL 의 경합</b>이라 MockMvc 가 필요 없다.
 *
 * <p>{@code @Transactional} 도 없다 — 붙이면 스레드 20개가 <b>각자의 트랜잭션</b>을 여는
 * 이 테스트의 전제가 사라진다.
 */
@SpringBootTest
class ChatMessageIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String ORIGIN_KIND = "CHATMSG_TEST";

    /** 방의 출처 쌍과 사용자 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired
    private ChatRoomService chatRooms;

    @Autowired
    private ChatSenderNames senderNames;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JdbcTemplate jdbc;

    // ─────────────────── 완료 조건 1 — 20 스레드, 1..20 이 빠짐없이 한 번씩 ───────────────────

    @Test
    @DisplayName("한 방에 스레드 20개가 동시에 넣으면 room_seq 가 1..20 이다 — 건너뛴 숫자도 중복도 없다")
    void twentyThreadsSendingAtOnce_getEveryNumberFromOneToTwentyExactlyOnce() throws Exception {
        Room room = room("동시 전송");
        List<Long> senders = new ArrayList<>();
        for (int i = 0; i < 20; i++) {
            senders.add(memberOf(room));
        }

        List<Object> results = allAtTheSameMoment(senders.stream()
                .map(userId -> (ThrowingSupplier) () -> chatRooms.postMessage(
                        room.id(), userId, "보호자", "동시에 보냅니다", null, null))
                .toList());

        List<Long> assigned = results.stream()
                .filter(ChatMessageView.class::isInstance)
                .map(ChatMessageView.class::cast)
                .map(ChatMessageView::roomSeq)
                .sorted()
                .toList();

        assertThat(results)
                .as("""
                        하나라도 예외가 났다면 그 사람에게는 전송 실패 화면이 뜬 것이다. \
                        번호가 맞는 것만으로는 부족하다 — 실패한 요청은 애초에 번호를 못 받는다.
                        %s""", results.stream().filter(r -> !(r instanceof ChatMessageView)).toList())
                .allMatch(ChatMessageView.class::isInstance);
        assertThat(assigned)
                .as("""
                        건너뛴 숫자가 있으면 클라이언트의 afterSeq 폴링이 그 자리에서 멈추거나 \
                        (다시 오지 않을 번호를 기다린다) 미읽음이 영영 0 이 되지 않는다.
                        중복이 있으면 UNIQUE (room_id, room_seq) 가 뒤에 온 INSERT 를 거부해 \
                        그 사람에게 500 이 나간다 (📌 #86 원칙 5 · ADR-0011 결정 2).""")
                .containsExactlyElementsOf(oneToTwenty());

        assertThat(messageCount(room)).isEqualTo(20);
        assertThat(lastSeqOf(room))
                .as("발급 카운터와 실제 마지막 번호가 갈리면 미읽음(last_seq − last_read_seq)이 틀린다")
                .isEqualTo(20L);
    }

    // ─────────────────── 완료 조건 2 — 방마다 1부터, 서로 영향 없음 ───────────────────

    @Test
    @DisplayName("서로 다른 두 방의 room_seq 는 각각 1부터 시작하고 서로를 밀지 않는다")
    void eachRoomCountsFromOneOnItsOwn() {
        Room family = room("우리 가족");
        Room crew = room("서울숲 산책 크루");
        long dad = memberOf(family);
        long walker = memberOf(crew);

        long first = chatRooms.postMessage(family.id(), dad, "보리아빠", "밥 줬어요", null, null)
                .roomSeq();
        long second = chatRooms.postMessage(family.id(), dad, "보리아빠", "산책도 다녀왔어요", null, null)
                .roomSeq();
        long crewFirst = chatRooms.postMessage(crew.id(), walker, "산책러", "오늘 7시요", null, null)
                .roomSeq();

        assertThat(first).isEqualTo(1L);
        assertThat(second).isEqualTo(2L);
        assertThat(crewFirst)
                .as("""
                        번호가 전역이면 방 하나가 시끄러울 때 조용한 방의 미읽음 숫자가 함께 튄다. \
                        발급기가 방마다 하나(chat_room.last_seq)인 것이 그 뜻이다.""")
                .isEqualTo(1L);
    }

    // ─────────────────── 완료 조건 3 — 탈퇴해도 메시지는 남고 이름은 "알 수 없음" ───────────────────

    @Test
    @DisplayName("보낸 사람이 탈퇴해도 메시지 행이 남고, 이름은 '알 수 없음' 이다 — '익명' 도 '탈퇴한 사용자' 도 아니다")
    void whenTheSenderWithdraws_theMessageStaysAndTheNameFallsBackToUnknown() {
        Room room = room("탈퇴 확인");
        User leaver = user("떠나는사람");
        joinAsMember(room, leaver.getId());

        chatRooms.postMessage(room.id(), leaver.getId(), leaver.displayName(),
                "먼저 갈게요", null, null);
        userRepository.deleteById(leaver.getId());

        List<ChatMessageView> after = chatRooms.messagesAfter(room.id(), 0, 50);

        assertThat(after)
                .as("""
                        sender_user_id 에 users FK 를 걸고 ON DELETE CASCADE 를 주면 이 행이 \
                        사라진다. 그러면 남는 것은 대답만 있고 질문이 없는 대화다 (ADR-0011 결정 4).""")
                .hasSize(1);
        assertThat(senderNames.of(after.get(0).senderUserId()))
                .as("""
                        '익명' 은 앱에서 이미 '본인이 이름을 안 붙인 것' 을 뜻하고 \
                        (feed_screen.dart '표시 이름 (비우면 익명)'), '탈퇴한 사용자' 는 방 안 모두에게 \
                        '이 사람이 나갔다' 를 알리는 것이라 본인이 동의한 적 없는 공개다 (#78).""")
                .isEqualTo("알 수 없음")
                .isEqualTo(User.UNKNOWN_DISPLAY_NAME);
        assertThat(after.get(0).senderNameAtSendTime())
                .as("스냅샷은 '그때 방 안의 사람들이 본 이름' 이라 남는다 — 응답의 이름이 아니다")
                .isEqualTo("떠나는사람");
    }

    // ─────────────────── 완료 조건 4 — 닉네임을 바꾸면 과거 메시지도 따라 바뀐다 ───────────────────

    @Test
    @DisplayName("닉네임을 바꾸면 그 사람의 과거 메시지 응답도 새 닉네임으로 나온다 — 카카오·라인이 그렇다")
    void renamingYourselfRenamesYouInEveryMessageYouAlreadySent() {
        Room room = room("개명 확인");
        User user = user("보리아빠");
        joinAsMember(room, user.getId());

        chatRooms.postMessage(room.id(), user.getId(), user.displayName(), "안녕하세요", null, null);

        user.setNickname("보리집사");
        userRepository.saveAndFlush(user);

        ChatMessageView past = chatRooms.messagesAfter(room.id(), 0, 50).get(0);

        assertThat(senderNames.of(past.senderUserId()))
                .as("""
                        스냅샷을 그대로 응답에 실으면 이름을 바꾼 사람이 자기 과거 대화에서만 옛 \
                        이름으로 남는다 — 같은 화면 안에서 한 사람이 두 이름으로 보인다 (#78 완료 조건 4).""")
                .isEqualTo("보리집사");
        assertThat(past.senderNameAtSendTime())
                .as("스냅샷은 바뀌지 않는다. 둘은 서로 다른 질문에 답한다")
                .isEqualTo("보리아빠");
    }

    // ─────────────────── 발급은 인가에 지면 함께 되돌아간다 ───────────────────

    @Test
    @DisplayName("멤버가 아닌 사람이 보내면 403 이고, 그 방의 번호를 하나도 쓰지 않는다")
    void aRejectedSendBurnsNoNumber() {
        Room room = room("인가 확인");
        long member = memberOf(room);
        long outsider = 900_000L + SEQUENCE.incrementAndGet();

        chatRooms.postMessage(room.id(), member, "보호자", "첫 줄", null, null);

        assertThatThrownBy(() ->
                chatRooms.postMessage(room.id(), outsider, "남", "여기 껴도 되나요", null, null))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("403");

        assertThat(lastSeqOf(room))
                .as("""
                        AUTO_INCREMENT 였다면 실패한 요청이 번호를 하나 태우고 그 자리가 영영 \
                        빈다. room_seq 는 같은 트랜잭션 안의 UPDATE 라 롤백이 발급을 함께 \
                        되돌린다 — 빈틈이 안 생기는 이유가 그것이다.""")
                .isEqualTo(1L);

        assertThat(chatRooms.postMessage(room.id(), member, "보호자", "둘째 줄", null, null).roomSeq())
                .as("되돌아간 번호를 다음 사람이 그대로 받는다")
                .isEqualTo(2L);
    }

    @Test
    @DisplayName("강퇴된(removed_at 이 찍힌) 사람은 더 보낼 수 없다 — 행이 남아 있는 것과 멤버인 것은 다르다")
    void aRemovedMemberCannotKeepTalking() {
        Room room = room("강퇴 확인");
        long member = memberOf(room);
        chatRooms.postMessage(room.id(), member, "보호자", "있을 때", null, null);

        jdbc.update("UPDATE chat_room_member SET removed_at = NOW(6) "
                + "WHERE room_id = ? AND user_id = ?", room.id(), member);

        assertThatThrownBy(() ->
                chatRooms.postMessage(room.id(), member, "보호자", "나가고 나서", null, null))
                .as("존재 여부가 아니라 removed_at 을 봐야 한다 — 강퇴된 사람의 행은 남아 있다")
                .isInstanceOf(ResponseStatusException.class);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Room(long id) { }

    /** 방 하나. 출처 쌍은 테스트마다 다르게 준다 — {@code UNIQUE (origin_kind, origin_ref)} 때문이다. */
    private Room room(String name) {
        long serial = SEQUENCE.incrementAndGet();
        long owner = 800_000L + serial;
        ChatRoomView view = chatRooms.openRoom(
                ORIGIN_KIND, "%d-%d".formatted(System.nanoTime(), serial), name, "가족", owner);
        return new Room(view.id());
    }

    /** 이 방의 살아 있는 멤버 한 명. <b>공개 경로로</b> 넣는다 — 발급·참여가 실제로 하는 일이다. */
    private long memberOf(Room room) {
        long userId = 700_000L + SEQUENCE.incrementAndGet();
        joinAsMember(room, userId);
        return userId;
    }

    private void joinAsMember(Room room, long userId) {
        long ownerId = jdbc.queryForObject(
                "SELECT user_id FROM chat_room_member WHERE room_id = ? AND role = 'OWNER'",
                Long.class, room.id());
        String code = chatRooms.issueInvite(room.id(), ownerId).code();
        chatRooms.joinByInviteCode(code, userId);
    }

    private User user(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        return userRepository.saveAndFlush(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("chatmsg-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private long messageCount(Room room) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM chat_message WHERE room_id = ?", Long.class, room.id());
    }

    private long lastSeqOf(Room room) {
        return jdbc.queryForObject(
                "SELECT last_seq FROM chat_room WHERE id = ?", Long.class, room.id());
    }

    private static List<Long> oneToTwenty() {
        List<Long> expected = new ArrayList<>();
        for (long i = 1; i <= 20; i++) {
            expected.add(i);
        }
        return expected;
    }

    private interface ThrowingSupplier {
        Object get() throws Exception;
    }

    /**
     * 여러 호출을 <b>실제로 같은 순간에</b> 출발시킨다 — {@link CyclicBarrier} 가 출발선이다.
     *
     * <p>{@code FamilyGroupInviteIntegrationTest.joinAtTheSameMoment} 와 같은 지그다.
     * 예외를 삼키지 않고 결과 자리에 넣는다 — 던져진 예외는 그 사용자에게 실패 화면이
     * 나갔다는 뜻이라 단언의 대상이지 테스트 오류가 아니다.
     */
    private static List<Object> allAtTheSameMoment(List<ThrowingSupplier> calls) throws Exception {
        int size = calls.size();
        CyclicBarrier startLine = new CyclicBarrier(size);
        Object[] results = new Object[size];
        List<Thread> threads = new ArrayList<>();

        for (int i = 0; i < size; i++) {
            final int index = i;
            Thread thread = new Thread(() -> {
                try {
                    startLine.await();
                    results[index] = calls.get(index).get();
                } catch (Exception thrown) {
                    results[index] = thrown.getClass().getSimpleName() + ": " + thrown.getMessage();
                }
            });
            threads.add(thread);
            thread.start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        return Arrays.asList(results);
    }
}

package com.heattrip.heat_trip_backend.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.heattrip.heat_trip_backend.chatweb.ChatMessagePageResponse;
import com.heattrip.heat_trip_backend.chatweb.ChatMessageResponse;
import com.heattrip.heat_trip_backend.chatweb.ChatMessages;
import com.heattrip.heat_trip_backend.chatweb.ChatRoomResponse;
import com.heattrip.heat_trip_backend.chatweb.ChatRooms;
import com.heattrip.heat_trip_backend.moderation.Blocks;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 가리기 — 이슈 #82 완료 조건 3.
 *
 * <h2>여기서 재는 것 셋</h2>
 * <ol>
 *   <li><b>과거·미래 모두 접힌다.</b> 가리기 전에 한 말과 가린 뒤에 한 말이 같이 접혀야
 *       한다 — "지금부터" 만 막으면 사용자가 가린 이유였던 그 메시지가 화면에 남는다.</li>
 *   <li><b>다른 사람 화면은 그대로다.</b> 가리기는 내 화면의 설정이고 삭제가 아니다.</li>
 *   <li><b>목록에서 빠지지 않는다.</b> 빼면 그 {@code roomSeq} 가 도달하지 않아 미읽음
 *       뱃지가 영원히 남는다 — 소프트 삭제를 톰스톤으로 내려주는 것과 같은 이유다.</li>
 * </ol>
 *
 * <p>3번이 이 파일에서 제일 중요하다. 계약이 원래 "목록에서 빼고 내려줍니다" 라고 적혀
 * 있었고, 그대로 만들었으면 <b>가린 사람의 뱃지가 안 지워지는 버그</b>가 됐다.
 *
 * <h2>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 의도다</h2>
 * <p>{@code ChatMessageIntegrationTest} 와 글자 그대로 같아야 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest
class ChatBlockIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String ORIGIN_KIND = "CHATBLOCK_TEST";
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired
    private Blocks blocks;

    @Autowired
    private ChatRoomService roomService;

    @Autowired
    private ChatMessages chatMessages;

    @Autowired
    private ChatRooms chatRooms;

    @Autowired
    private UserRepository users;

    @Test
    @DisplayName("가리기 전에 한 말도 함께 접힌다 — 과거·미래 모두다")
    void pastMessagesAreHiddenToo() {
        Fixture f = fixture();
        send(f, f.noisy, "가리기 전에 한 말");

        blocks.block(f.reader.getId(), f.noisy.getId());
        send(f, f.noisy, "가린 뒤에 한 말");

        assertThat(pageOf(f, f.reader)).extracting(ChatMessageResponse::hiddenByBlock)
                .as("""
                        "지금부터" 만 막으면 사용자가 가린 이유였던 바로 그 메시지가 화면에 남는다.
                        """)
                .containsExactly(true, true);
    }

    @Test
    @DisplayName("다른 사람 화면에는 그대로 남는다 — 가리기는 삭제가 아니다")
    void othersStillSeeIt() {
        Fixture f = fixture();
        send(f, f.noisy, "누군가는 계속 봐야 하는 말");
        blocks.block(f.reader.getId(), f.noisy.getId());

        assertThat(pageOf(f, f.reader)).singleElement()
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(true);
        assertThat(pageOf(f, f.bystander)).singleElement()
                .as("내가 가렸다고 남의 화면에서 사라지면 그건 가리기가 아니라 삭제다")
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(false);
    }

    @Test
    @DisplayName("접혀도 목록에서 빠지지 않고 본문도 온다 — 뱃지와 보기 둘 다를 위해서다")
    void hiddenMessagesStayInTheListWithTheirBody() {
        Fixture f = fixture();
        long seq = send(f, f.noisy, "접히지만 사라지지는 않는 말");
        blocks.block(f.reader.getId(), f.noisy.getId());

        ChatMessagePageResponse page = chatMessages.page(
                f.roomId, f.reader.getId(), 0L, null, 50);

        assertThat(page.items()).singleElement().satisfies(item -> {
            assertThat(item.roomSeq())
                    .as("""
                            빼면 이 번호가 클라이언트에 도달하지 않는다. 미읽음이
                            room.last_seq - member.last_read_seq 뺄셈이라 읽음 커서가 그 번호를
                            못 넘고 뱃지가 영원히 안 지워진다 (ADR-0011).
                            """)
                    .isEqualTo(seq);
            assertThat(item.body())
                    .as("""
                            가려진 자리에 "보기" 가 있다. 본문을 지워 내리면 그것을 누를 때
                            요청이 한 번 더 필요해지고, 그 요청은 가린 사람만 부르는 경로가 된다.
                            """)
                    .isEqualTo("접히지만 사라지지는 않는 말");
        });
        assertThat(page.lastSeq()).isEqualTo(seq);
    }

    @Test
    @DisplayName("방 목록 미리보기도 접힌다 — 방 안에서 접고 목록에서 새면 안 된다")
    void theRoomListPreviewIsHiddenToo() {
        Fixture f = fixture();
        send(f, f.noisy, "목록으로 새면 안 되는 말");
        blocks.block(f.reader.getId(), f.noisy.getId());

        assertThat(roomOf(f, f.reader).lastMessage().hiddenByBlock())
                .as("방 안에서 접어 놓고 목록에서 그대로 보여 주면 거기로 샌다")
                .isTrue();
        assertThat(roomOf(f, f.bystander).lastMessage().hiddenByBlock()).isFalse();
    }

    @Test
    @DisplayName("풀면 다시 보인다")
    void unblockingBringsItBack() {
        Fixture f = fixture();
        send(f, f.noisy, "다시 보여야 하는 말");
        blocks.block(f.reader.getId(), f.noisy.getId());
        blocks.unblock(f.reader.getId(), f.noisy.getId());

        assertThat(pageOf(f, f.reader)).singleElement()
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(false);
    }

    @Test
    @DisplayName("가린 적 없는 사람의 가리기를 풀어도 성공이다")
    void unblockingWhatWasNeverBlockedIsFine() {
        Fixture f = fixture();

        blocks.unblock(f.reader.getId(), f.noisy.getId());

        assertThat(blocks.blockedBy(f.reader.getId()))
                .as("있고 없고를 알려 주면 가려 뒀는지를 응답으로 물어볼 수 있게 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("두 번 가려도 행은 하나다")
    void blockingTwiceIsIdempotent() {
        Fixture f = fixture();

        assertThat(blocks.block(f.reader.getId(), f.noisy.getId())).isTrue();
        assertThat(blocks.block(f.reader.getId(), f.noisy.getId()))
                .as("두 번째는 아무것도 바꾸지 않는다")
                .isFalse();
        assertThat(blocks.blockedBy(f.reader.getId())).containsExactly(f.noisy.getId());
    }

    @Test
    @DisplayName("가리기는 한 방향이다 — 내가 가려도 상대 화면은 안 바뀐다")
    void blockingIsOneWay() {
        Fixture f = fixture();
        send(f, f.reader, "내가 한 말");
        blocks.block(f.reader.getId(), f.noisy.getId());

        assertThat(pageOf(f, f.noisy)).singleElement()
                .as("""
                        내가 가린 것이 상대에게 보이면 그 자체가 통지다.
                        신고가 무통지인 것과 같은 이유로 여기도 조용해야 한다.
                        """)
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(false);
    }

    @Test
    @DisplayName("자기 자신은 못 가린다")
    void cannotBlockYourself() {
        Fixture f = fixture();

        assertThatThrownBy(() -> blocks.block(f.reader.getId(), f.reader.getId()))
                .as("허용하면 자기 메시지가 자기 화면에서 접힌다. 그건 사용자가 원한 상태가 아니다")
                .isInstanceOf(ResponseStatusException.class);
    }

    @Test
    @DisplayName("가리기는 방과 무관하다 — 한 번 가리면 모든 방에서 접힌다")
    void blockingSpansEveryRoom() {
        Fixture first = fixture();
        Fixture second = fixture(first.reader, first.noisy, first.bystander);
        send(first, first.noisy, "첫 방에서 한 말");
        send(second, second.noisy, "둘째 방에서 한 말");

        blocks.block(first.reader.getId(), first.noisy.getId());

        assertThat(pageOf(first, first.reader)).singleElement()
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(true);
        assertThat(pageOf(second, second.reader)).singleElement()
                .as("방마다 따로 걸게 하면 방이 늘 때마다 사용자가 같은 일을 다시 해야 한다")
                .extracting(ChatMessageResponse::hiddenByBlock).isEqualTo(true);
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private record Fixture(long roomId, User reader, User noisy, User bystander) {}

    private Fixture fixture() {
        return fixture(signUp("가리는 사람"), signUp("가려질 사람"), signUp("옆에 있는 사람"));
    }

    private Fixture fixture(User reader, User noisy, User bystander) {
        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = roomService.openRoom(
                ORIGIN_KIND, "block-" + System.nanoTime() + "-" + serial,
                "가리기 테스트방", "FAMILY", reader.getId());

        String code = roomService.issueInvite(room.id(), reader.getId()).code();
        roomService.joinByInviteCode(code, noisy.getId());
        roomService.joinByInviteCode(code, bystander.getId());

        return new Fixture(room.id(), reader, noisy, bystander);
    }

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("block-%d@example.com".formatted(System.nanoTime()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private long send(Fixture f, User sender, String body) {
        return roomService.postMessage(
                f.roomId, sender.getId(), sender.getNickname(), body, "text", null).roomSeq();
    }

    private List<ChatMessageResponse> pageOf(Fixture f, User reader) {
        return chatMessages.page(f.roomId, reader.getId(), 0L, null, 50).items();
    }

    private ChatRoomResponse roomOf(Fixture f, User reader) {
        return chatRooms.of(reader.getId()).stream()
                .filter(r -> r.id() == f.roomId)
                .findFirst()
                .orElseThrow(() -> new AssertionError("방 목록에 " + f.roomId + " 이 없다"));
    }
}

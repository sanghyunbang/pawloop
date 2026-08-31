package com.heattrip.heat_trip_backend.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 강퇴와 재입장 금지, 그리고 만 14세 게이트 — 이슈 #82 완료 조건 4 · 5 · 10.
 *
 * <h2>여기서 재는 것</h2>
 * <p><b>강퇴당한 계정이 유효한 초대코드로도 못 들어온다.</b> 그리고 그 사람이 쓴 메시지는
 * 방에 남아 있다 — 지우면 신고 근거가 사라진다.
 *
 * <h2>판정은 이미 있었고 없던 것은 강퇴였다</h2>
 * <p>{@code joinByInviteCode} 의 {@code isRejoinBlocked()} 검사는 #75 때부터 서 있었다.
 * 그런데 {@code rejoin_blocked} 를 {@code true} 로 만드는 코드가 <b>한 줄도 없어서</b>
 * 그 검사는 한 번도 걸린 적이 없다. 이 파일이 그것을 처음으로 걸리게 한다.
 *
 * <h2>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 의도다</h2>
 * <p>{@code ChatMessageIntegrationTest} 와 글자 그대로 같아야 컨텍스트 캐시를 공유한다(#21).
 * {@code @Transactional} 이 없는 것도 의도다 — 강퇴가 커밋된 뒤에 다시 들어와 보는 판이다.
 */
@SpringBootTest
class ChatKickIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String ORIGIN_KIND = "CHATKICK_TEST";
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired
    private ChatRoomService roomService;

    @Autowired
    private UserRepository users;

    @Autowired
    private JdbcTemplate jdbc;

    // ─────────────────────────── 완료 조건 4 ───────────────────────────

    @Test
    @DisplayName("강퇴당하면 유효한 초대코드로도 못 들어온다")
    void aKickedMemberCannotComeBackWithAValidCode() {
        Fixture f = fixture();
        String code = f.freshCode();

        roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId());

        assertThatThrownBy(() -> roomService.joinByInviteCode(code, f.member.getId()))
                .as("""
                        코드는 아직 살아 있다. 막는 것은 코드의 상태가 아니라 그 사람이
                        강퇴당했다는 사실이어야 한다.
                        """)
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.FORBIDDEN);

        assertThat(roomService.isLiveMember(f.roomId, f.member.getId())).isFalse();
    }

    @Test
    @DisplayName("강퇴당한 사람이 쓴 메시지는 방에 남는다 — 지우면 신고 근거가 사라진다")
    void theirMessagesStay() {
        Fixture f = fixture();
        long seq = send(f, f.member, "강퇴 전에 남긴 말");

        roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId());

        assertThat(roomService.messagesAfter(f.roomId, 0, 50))
                .as("디스코드도 메시지 삭제 옵션은 kick 이 아니라 ban 에만 붙였다")
                .singleElement()
                .satisfies(message -> {
                    assertThat(message.roomSeq()).isEqualTo(seq);
                    assertThat(message.body()).isEqualTo("강퇴 전에 남긴 말");
                });
    }

    @Test
    @DisplayName("멤버 행이 남아서 last_read_seq 도 남는다 — 지우면 미읽음이 처음부터 다시 쌓인다")
    void theMemberRowSurvivesWithItsWatermark() {
        Fixture f = fixture();
        send(f, f.owner, "한 줄");
        roomService.markRead(f.roomId, f.member.getId(), 1);

        roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId());

        assertThat(memberRow(f.roomId, f.member.getId()))
                .as("행 자체가 사라지면 재입장 금지를 걸 자리도 읽음 커서도 함께 사라진다")
                .isNotNull()
                .containsEntry("last_read_seq", 1L)
                .containsEntry("removed_by", f.owner.getId());
    }

    @Test
    @DisplayName("두 번 내보내도 오류가 아니다 — 결과가 같다")
    void kickingTwiceIsIdempotent() {
        Fixture f = fixture();

        assertThat(roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId())).isTrue();
        assertThat(roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId()))
                .as("두 번째는 아무것도 바꾸지 않는다. 방장에게는 결과가 같다 — 그 사람은 없다")
                .isFalse();
    }

    @Test
    @DisplayName("방장이 아니면 못 내보낸다")
    void onlyTheOwnerCanKick() {
        Fixture f = fixture();
        User another = signUp("그냥 멤버");
        roomService.joinByInviteCode(f.freshCode(), another.getId());

        assertThatThrownBy(() ->
                roomService.removeMember(f.roomId, another.getId(), f.member.getId()))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("방장은 자기를 못 내보낸다 — 방장 없는 방이 생긴다")
    void theOwnerCannotKickThemselves() {
        Fixture f = fixture();

        assertThatThrownBy(() ->
                roomService.removeMember(f.roomId, f.owner.getId(), f.owner.getId()))
                .as("허용하면 그 방은 초대코드도 못 내고 강퇴도 못 하는 방이 된다")
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.BAD_REQUEST);
    }

    @Test
    @DisplayName("그 방에 없는 사람을 지목하면 404 다")
    void kickingSomeoneWhoWasNeverThere() {
        Fixture f = fixture();
        User stranger = signUp("한 번도 안 온 사람");

        assertThatThrownBy(() ->
                roomService.removeMember(f.roomId, f.owner.getId(), stranger.getId()))
                .as("방장이 부르는 것이라 방 존재 여부가 새지 않는다. 계약도 404 를 선언했다")
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    // ─────────────────────────── 재입장 금지 해제 ───────────────────────────

    @Test
    @DisplayName("방장이 풀면 다시 들어올 수 있다 — 다만 자동으로 돌아오지는 않는다")
    void theOwnerCanLiftTheBan() {
        Fixture f = fixture();
        roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId());

        assertThat(roomService.allowRejoin(f.roomId, f.owner.getId(), f.member.getId())).isTrue();

        assertThat(roomService.isLiveMember(f.roomId, f.member.getId()))
                .as("""
                        푸는 것은 금지뿐이다. 자동으로 넣으면 방장이 "금지만 풀려고" 누른 버튼이
                        사람을 방에 다시 넣는 버튼이 된다.
                        """)
                .isFalse();

        roomService.joinByInviteCode(f.freshCode(), f.member.getId());
        assertThat(roomService.isLiveMember(f.roomId, f.member.getId())).isTrue();
    }

    @Test
    @DisplayName("금지 상태가 아닌 사람을 풀어도 오류가 아니다")
    void liftingWhatWasNeverSetIsFine() {
        Fixture f = fixture();

        assertThat(roomService.allowRejoin(f.roomId, f.owner.getId(), f.member.getId())).isFalse();
        assertThat(roomService.isLiveMember(f.roomId, f.member.getId())).isTrue();
    }

    @Test
    @DisplayName("방장이 아니면 못 푼다 — 강퇴당한 본인이 스스로 풀 수 없다")
    void onlyTheOwnerCanLiftTheBan() {
        Fixture f = fixture();
        roomService.removeMember(f.roomId, f.owner.getId(), f.member.getId());

        assertThatThrownBy(() ->
                roomService.allowRejoin(f.roomId, f.member.getId(), f.member.getId()))
                .as("강퇴당한 사람은 이미 멤버가 아니라 requireOwner 에서 먼저 걸린다")
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    // ─────────────────────────── 완료 조건 5 ───────────────────────────

    @Test
    @DisplayName("허용 목록에 없는 종류의 방에는 못 들어간다")
    void aRoomKindOutsideTheAllowListIsRefused() {
        Fixture f = fixture();
        User minor = signUp("만 14세 미만");

        assertThatThrownBy(() -> roomService.joinByInviteCode(
                f.freshCode(), minor.getId(), Set.of("FAMILY")))
                .as("""
                        이 방의 origin_kind 는 CHATKICK_TEST 라 목록에 없다.
                        chat 은 그 문자열의 뜻을 모른다 — 대조만 한다.
                        """)
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("허용 목록에 있으면 들어간다")
    void anAllowedRoomKindGoesThrough() {
        Fixture f = fixture();
        User minor = signUp("만 14세 미만");

        roomService.joinByInviteCode(f.freshCode(), minor.getId(), Set.of(ORIGIN_KIND));

        assertThat(roomService.isLiveMember(f.roomId, minor.getId())).isTrue();
    }

    @Test
    @DisplayName("목록이 null 이면 제한이 없다 — 만 14세 이상이 여기로 온다")
    void aNullAllowListMeansNoRestriction() {
        Fixture f = fixture();
        User adult = signUp("만 14세 이상");

        roomService.joinByInviteCode(f.freshCode(), adult.getId(), null);

        assertThat(roomService.isLiveMember(f.roomId, adult.getId())).isTrue();
    }

    @Test
    @DisplayName("막힌 참여는 초대코드의 사용 횟수를 쓰지 않는다")
    void arefusedJoinDoesNotConsumeAUse() {
        Fixture f = fixture();
        User minor = signUp("돌려보내질 사람");
        String code = f.freshCode();

        assertThatThrownBy(() -> roomService.joinByInviteCode(code, minor.getId(), Set.of("FAMILY")))
                .isInstanceOf(ResponseStatusException.class);

        // 같은 코드로 제한 없이 들어오면 성공해야 한다 — 앞의 거절이 코드를 소모했다면 못 들어온다.
        User adult = signUp("들어올 사람");
        roomService.joinByInviteCode(code, adult.getId(), null);

        assertThat(roomService.isLiveMember(f.roomId, adult.getId()))
                .as("예외가 트랜잭션을 통째로 되돌리므로 못 들어온 요청은 사용 횟수를 쓰지 않는다")
                .isTrue();
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private final class Fixture {
        private final long roomId;
        private final User owner;
        private final User member;

        Fixture(long roomId, User owner, User member) {
            this.roomId = roomId;
            this.owner = owner;
            this.member = member;
        }

        /** 사용 횟수를 서로 잡아먹지 않게 매번 새로 뽑는다. */
        String freshCode() {
            return roomService.issueInvite(roomId, owner.getId()).code();
        }
    }

    private Fixture fixture() {
        User owner = signUp("방장");
        User member = signUp("내보내질 사람");
        long serial = SEQUENCE.incrementAndGet();

        ChatRoomView room = roomService.openRoom(
                ORIGIN_KIND, "kick-" + System.nanoTime() + "-" + serial,
                "강퇴 테스트방", "가족", owner.getId());
        Fixture f = new Fixture(room.id(), owner, member);
        roomService.joinByInviteCode(f.freshCode(), member.getId());
        return f;
    }

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("kick-%d@example.com".formatted(System.nanoTime()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private long send(Fixture f, User sender, String body) {
        return roomService.postMessage(
                f.roomId, sender.getId(), sender.getNickname(), body, "text", null).roomSeq();
    }

    private java.util.Map<String, Object> memberRow(long roomId, long userId) {
        List<java.util.Map<String, Object>> rows = jdbc.queryForList(
                "select last_read_seq, removed_by, removed_at, rejoin_blocked "
                        + "from chat_room_member where room_id = ? and user_id = ?",
                roomId, userId);
        return rows.isEmpty() ? null : rows.get(0);
    }
}

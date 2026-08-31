package com.heattrip.heat_trip_backend.social;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.social.dto.CardDto;
import com.heattrip.heat_trip_backend.social.dto.CommentDto;
import com.heattrip.heat_trip_backend.social.entity.EmotionCard;
import com.heattrip.heat_trip_backend.social.service.SocialService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.UserService;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

/**
 * 탈퇴한 사람의 이름이 커뮤니티에 계속 뜨던 것. (이슈 #82 완료 조건 8 · 11)
 *
 * <h2>무엇이 새고 있었나</h2>
 * <p>{@code emotion_card.handle} 과 {@code card_comment.handle} 은 <b>쓴 시점의 이름 스냅샷</b>이다.
 * {@code SocialService} 는 그것을 그대로 응답에 실었고, {@code users} 행이 사라져도 스냅샷은 남으므로
 * <b>탈퇴한 사람의 닉네임이 카드와 댓글에 계속 떴다.</b> 탈퇴 화면은 "복구할 수 없습니다" 라고
 * 말하는데 커뮤니티에는 그 사람이 남아 있는 상태였다.
 *
 * <h2>여기가 진짜로 탈퇴시키는 이유</h2>
 * <p>{@code userRepository.delete(...)} 를 직접 부르지 않고 <b>{@link UserService#deleteMe} 로</b>
 * 지운다. 그게 앱의 탈퇴 버튼이 실제로 부르는 경로({@code DELETE /auth/me})이고, 만약 나중에
 * 탈퇴가 소프트 삭제로 바뀌면 <b>이 테스트가 그때 빨개져야</b> 하기 때문이다. 행을 직접 지우면
 * 그 변화를 못 잡는다.
 */
@SpringBootTest
@Transactional
class SocialWithdrawnHandleIntegrationTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private SocialService socialService;

    @Autowired
    private UserService userService;

    @Autowired
    private UserRepository userRepository;

    private User signUp(String nickname) {
        return userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("social-%d@example.com".formatted(System.nanoTime()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private EmotionCard shareCard(User author) {
        return socialService.share(
                author.getId(), author.getNickname(), "기쁨", "오늘 산책 좋았어요", "한강공원", null);
    }

    @Test
    @DisplayName("탈퇴하면 그 사람이 쓴 카드의 이름이 사라진다 — 남은 사람 것은 그대로다")
    void withdrawnAuthorLosesTheirNameOnCards() {
        User leaving = signUp("떠날사람");
        User staying = signUp("남을사람");
        Long leavingCardId = shareCard(leaving).getId();
        Long stayingCardId = shareCard(staying).getId();

        userService.deleteMe(leaving.getId());

        List<CardDto> feed = socialService.feed(staying.getId(), 50);

        assertThat(card(feed, leavingCardId).handle())
                .as("""
                        탈퇴했는데 이름이 그대로 떴다. 스냅샷을 그대로 실으면 이렇게 된다.

                        null 이 아니라 "알 수 없음" 이어야 한다 — null 은 앱이 "익명" 으로 그리고,
                        그건 익명으로 남긴 글이라는 뜻이라 사실과 다르다.
                        """)
                .isEqualTo(User.UNKNOWN_DISPLAY_NAME);

        assertThat(card(feed, stayingCardId).handle())
                .as("남아 있는 사람까지 가리면 그건 고친 게 아니라 다 지운 것이다")
                .isEqualTo("남을사람");
    }

    @Test
    @DisplayName("탈퇴하면 그 사람이 단 댓글의 이름도 사라진다")
    void withdrawnAuthorLosesTheirNameOnComments() {
        User owner = signUp("글쓴이");
        User leaving = signUp("댓글쓴이");
        Long cardId = shareCard(owner).getId();

        socialService.addComment(cardId, leaving.getId(), leaving.getNickname(), "귀엽네요");
        socialService.addComment(cardId, owner.getId(), owner.getNickname(), "고맙습니다");

        userService.deleteMe(leaving.getId());

        List<CommentDto> comments = socialService.comments(cardId);

        assertThat(comments).extracting(CommentDto::handle)
                .as("댓글도 같은 스냅샷을 쓴다. 카드만 고치면 절반만 고친 것이다")
                .containsExactlyInAnyOrder(User.UNKNOWN_DISPLAY_NAME, "글쓴이");
    }

    @Test
    @DisplayName("한 사람이 카드를 여럿 써도 이름이 그대로다")
    void manyCardsFromOnePersonStayIntact() {
        User author = signUp("여러장쓴사람");
        for (int i = 0; i < 30; i++) {
            shareCard(author);
        }

        // 여기서 재는 것은 시간이 아니라 구조다. 쿼리 수를 세는 장치가 이 저장소에 없어서
        // "id 마다 묻지 않는다" 는 WithdrawnUsersTest 가 목으로 직접 증명한다.
        List<CardDto> feed = socialService.feed(author.getId(), 50);

        assertThat(feed).hasSizeGreaterThanOrEqualTo(30);
        assertThat(feed).extracting(CardDto::handle)
                .as("살아 있는 사람이 쓴 카드는 몇 장이든 이름이 그대로다")
                .containsOnly("여러장쓴사람");
    }

    @Test
    @DisplayName("로그인 없이 남긴 글은 탈퇴와 다르다 — handle 이 null 이면 null 로 둔다")
    void anonymousIsNotWithdrawn() {
        User reader = signUp("읽는사람");
        EmotionCard anonymous = socialService.share(
                reader.getId(), null, "기쁨", "이름 없이 남깁니다", null, null);

        String handle = card(socialService.feed(reader.getId(), 50), anonymous.getId()).handle();

        assertThat(handle)
                .as("""
                        살아 있는 사람이 이름 없이 남긴 글이다. 여기에 "알 수 없음" 을 채우면
                        앱이 "익명" 으로 그리던 것을 탈퇴자로 바꿔 그린다 — 없던 사실을 만든 것이다.
                        """)
                .isNull();
    }

    private static CardDto card(List<CardDto> feed, Long id) {
        return feed.stream()
                .filter(c -> id.equals(c.id()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("피드에 카드 " + id + " 가 없다"));
    }
}

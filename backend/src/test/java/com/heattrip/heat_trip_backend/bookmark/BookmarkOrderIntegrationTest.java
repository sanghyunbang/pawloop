package com.heattrip.heat_trip_backend.bookmark;

import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import com.heattrip.heat_trip_backend.bookmark.repository.BookmarkRepository;
import com.heattrip.heat_trip_backend.bookmark.service.BookmarkService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 북마크 목록의 순서 — 이슈 #210({@code Bookmarks-medium-2}).
 *
 * <h2>왜 순서가 계약의 일이 되는가</h2>
 * <p>조회에 정렬이 없으면 <b>DB 임의 순서</b>다. 앱은 그것을 그대로 믿는다 —
 * {@code bookmark_repository_impl.dart} 가 응답에 {@code createdAt} 이 없으면
 * "서버가 준 순서를 신뢰" 하는 분기로 떨어지고, 화면의 "최신순" 이 사실이 아니게 된다.
 *
 * <p>동률을 {@code id} 로 깨는 것도 함께 잰다. 같은 초에 둘을 담으면 한 축으로는 순서가
 * 매 요청 달라진다 — 목록을 새로고침할 때마다 카드가 자리를 바꾼다.
 *
 * <h2>이 화면은 아직 탭으로 못 간다</h2>
 * <p>v2 {@code me_screen} 의 북마크 메뉴는 스낵바이고, {@code /bookmarks} 라우트는 보존된
 * 레거시 셸에 있다. 그래도 정렬은 지금 고친다 — 한 줄이고, v2 북마크(#94)가 붙는 날
 * <b>이미 맞는 상태</b>에서 시작한다.
 */
@SpringBootTest
@Transactional
class BookmarkOrderIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired BookmarkService bookmarks;
    @Autowired BookmarkRepository repository;
    @Autowired UserRepository users;

    @Test
    @DisplayName("최신순이다 — 정렬이 없으면 화면의 '최신순' 이 DB 임의 순서가 된다")
    void listIsNewestFirst() {
        User me = newUser();
        save(me, "오래된", LocalDateTime.of(2026, 1, 1, 9, 0));
        save(me, "최신", LocalDateTime.of(2026, 3, 1, 9, 0));
        save(me, "중간", LocalDateTime.of(2026, 2, 1, 9, 0));

        assertThat(contentIdsOf(bookmarks.findAll(me)))
                .containsExactly("최신", "중간", "오래된");
    }

    @Test
    @DisplayName("같은 시각이면 id 가 동률을 깬다 — 없으면 새로고침마다 카드가 자리를 바꾼다")
    void tiesAreBrokenById() {
        User me = newUser();
        LocalDateTime sameMoment = LocalDateTime.of(2026, 2, 1, 9, 0);
        Bookmark first = save(me, "먼저", sameMoment);
        Bookmark second = save(me, "나중", sameMoment);

        assertThat(second.getId())
                .as("이 테스트의 전제 — 나중에 저장한 것의 id 가 더 크다")
                .isGreaterThan(first.getId());
        assertThat(contentIdsOf(bookmarks.findAll(me)))
                .containsExactly("나중", "먼저");
    }

    @Test
    @DisplayName("남의 북마크는 안 섞인다")
    void listIsScopedToTheOwner() {
        User me = newUser();
        User other = newUser();
        save(me, "내것", LocalDateTime.of(2026, 1, 1, 9, 0));
        save(other, "남의것", LocalDateTime.of(2026, 5, 1, 9, 0));

        assertThat(contentIdsOf(bookmarks.findAll(me))).containsExactly("내것");
    }

    private static List<String> contentIdsOf(List<Bookmark> rows) {
        return rows.stream().map(Bookmark::getContentId).toList();
    }

    /**
     * {@code createdAt} 을 직접 심는다. {@code @PrePersist} 가 {@code now()} 를 넣으므로
     * 저장 뒤 다시 세팅해야 한다 — 안 그러면 셋이 같은 밀리초에 들어가 정렬을 못 잰다.
     */
    private Bookmark save(User owner, String contentId, LocalDateTime createdAt) {
        Bookmark saved = repository.saveAndFlush(
                Bookmark.builder().user(owner).contentId(contentId).build());
        saved.setCreatedAt(createdAt);
        return repository.saveAndFlush(saved);
    }

    private User newUser() {
        long serial = SEQUENCE.incrementAndGet();
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("bookmark-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .nickname("북마크")
                .build());
    }
}

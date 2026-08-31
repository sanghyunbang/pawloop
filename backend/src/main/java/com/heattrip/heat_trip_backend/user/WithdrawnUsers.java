package com.heattrip.heat_trip_backend.user;

import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import java.util.Collection;
import java.util.HashSet;
import java.util.Set;
import org.springframework.stereotype.Component;

/**
 * 탈퇴한 사용자를 가려내는 것. <b>{@code user} 모듈의 공개 표면이다.</b> (이슈 #82)
 *
 * <h2>왜 이 타입이 있어야 하는가</h2>
 * <p>{@code social} 이 커뮤니티 카드·댓글을 그릴 때 <b>작성 시점의 {@code handle} 스냅샷</b>을
 * 그대로 응답에 싣고 있었다. 그래서 <b>탈퇴해도 그 사람 닉네임이 계속 떴다.</b> 탈퇴 화면은
 * "복구할 수 없습니다" 라고 말하는데 커뮤니티에는 남아 있는 상태였다.
 *
 * <p>고치려면 "이 id 가 아직 있는가" 를 물어야 하는데, {@code social} 이
 * {@code user.repository.UserRepository} 를 직접 부르면 안 된다 — 규약이 이렇게 적어 뒀다
 * ({@code docs/02-architecture/backend-implementation-guide.md} §2.3).
 *
 * <blockquote>
 * 리포지토리를 남이 직접 부르는 것은 공용 어휘가 아니라 <b>그냥 새는 것</b>이다.
 * </blockquote>
 *
 * <p>그래서 {@code user} 가 <b>질문에 답하는 표면</b>을 하나 내준다. 패키지 루트라 그 자체로
 * 공개 표면이고 별도 선언이 필요 없다(#105 · #108).
 *
 * <h2>N+1 을 만들지 않는다</h2>
 * <p>한 번에 묻는다. 카드 100건({@code MAX_LIMIT})이면 사용자도 최대 100명이고, id 마다 따로
 * 물으면 쿼리가 100개가 된다. {@code SocialService} 는 리액션과 댓글 수에서 이미 같은 함정을
 * 피해 뒀고, 여기서 그것을 깨면 안 된다.
 *
 * <p>엔티티를 읽지 않고 <b>id 만</b> 가져온다 — 필요한 것이 존재 여부뿐이라 행을 영속성
 * 컨텍스트에 올릴 이유가 없다.
 */
@Component
public class WithdrawnUsers {

    private final UserRepository users;

    public WithdrawnUsers(UserRepository users) {
        this.users = users;
    }

    /**
     * 이 id 들 중 <b>이미 없는 것</b>.
     *
     * <p>{@code null} 은 걸러 낸다 — 로그인 없이 남긴 글은 {@code user_id} 가 비어 있고,
     * 그건 탈퇴가 아니라 처음부터 익명이다. 그 구분은 부르는 쪽이 유지한다.
     *
     * @return 탈퇴했거나 애초에 없는 id 들. 입력이 비면 빈 집합이고 <b>쿼리를 보내지 않는다</b>
     */
    public Set<Long> among(Collection<Long> candidateIds) {
        Set<Long> asked = new HashSet<>();
        for (Long id : candidateIds) {
            if (id != null) {
                asked.add(id);
            }
        }
        if (asked.isEmpty()) {
            return Set.of();
        }

        Set<Long> alive = new HashSet<>(users.findExistingIds(asked));
        asked.removeAll(alive);
        return asked;
    }
}

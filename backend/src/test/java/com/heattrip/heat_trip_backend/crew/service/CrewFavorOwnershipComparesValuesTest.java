package com.heattrip.heat_trip_backend.crew.service;

import com.heattrip.heat_trip_backend.user.entity.User;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * "그 사람이 나인가" 를 <b>값으로</b> 견주는가 — 이슈 #510.
 *
 * <h2>왜 통합 테스트가 아닌가</h2>
 * <p>끝에서 끝까지 도는 테스트로는 이 결함이 <b>안 보인다.</b> {@code spring.jpa.open-in-view}
 * 가 어디에도 안 적혀 있어 기본값 {@code true} 이고, 그러면 요청 하나가 영속성 컨텍스트를
 * 공유해 {@code @CurrentUser} 가 읽은 {@code User} 와 부탁의 {@code askedBy} 가 <b>같은
 * 인스턴스</b>다. 참조를 견줘도 참이 나온다. 그 설정을 끄는 날 — 또는 그 사용자를 다른
 * 트랜잭션에서 읽는 날 — id 가 127 을 넘는 사람은 무르기·거둬들이기가 전원 403 이 되고,
 * "자기 부탁은 자기가 못 맡는다" 는 반대로 풀린다.
 *
 * <p>그래서 재는 것을 <b>비교 그 자체</b>로 좁혔다. 인스턴스가 둘로 갈린 상태를 여기서 직접
 * 만든다 — 그 상태가 곧 OSIV 를 끈 다음날의 서버다. 스프링을 안 띄운다(#21).
 *
 * <p>{@code Long} 캐시가 {@code -128~127} 만 덮는 것이 이 결함의 핵심이라, 아래 둘째 테스트가
 * <b>작은 id 로는 지금도 통과한다</b>는 사실을 함께 박아 둔다. 기존 통합 테스트들이 왜 이것을
 * 못 잡았는지가 그 한 줄에 적혀 있어야 다음 사람이 같은 자리에 작은 id 테스트를 또 만들지
 * 않는다.
 */
class CrewFavorOwnershipComparesValuesTest {

    /** {@code Long} 캐시 밖의 id. 부를 때마다 새 인스턴스다. */
    private static Long idOutsideTheLongCache() {
        return Long.valueOf(4_211L);
    }

    @Test
    @DisplayName("같은 값의 다른 인스턴스는 같은 사람이다 — == 였다면 여기서 빨간불이다")
    void theSameIdInTwoInstancesIsStillMe() {
        Long fromTheRow = idOutsideTheLongCache();
        Long fromTheRequest = idOutsideTheLongCache();

        assertThat(fromTheRow)
                .as("전제가 무너지면(캐시에 들어오면) 이 테스트는 아무것도 못 잰다")
                .isNotSameAs(fromTheRequest)
                .isEqualTo(fromTheRequest);

        assertThat(CrewFavorService.isMe(userWith(fromTheRow), fromTheRequest))
                .as("OSIV 를 끄면 요청의 User 와 행의 User 가 다른 인스턴스로 온다")
                .isTrue();
    }

    @Test
    @DisplayName("127 이하는 참조를 견줘도 통과한다 — 작은 id 로 도는 테스트가 이것을 못 잡은 이유")
    void smallIdsPassEvenWhenTheComparisonIsWrong() {
        Long fromTheRow = Long.valueOf(7L);
        Long fromTheRequest = Long.valueOf(7L);

        assertThat(fromTheRow)
                .as("자바가 -128~127 을 캐시한다 — 그래서 여기서는 == 도 참이다")
                .isSameAs(fromTheRequest);
        assertThat(CrewFavorService.isMe(userWith(fromTheRow), fromTheRequest)).isTrue();
    }

    @Test
    @DisplayName("다른 사람은 다른 사람이다 — 값이 같을 때만 참이다")
    void anotherPersonIsNotMe() {
        assertThat(CrewFavorService.isMe(userWith(4_211L), 4_212L)).isFalse();
    }

    @Test
    @DisplayName("아무도 안 맡은 부탁의 takenBy 는 null 이다 — null 은 내가 아니다")
    void nobodyIsNotMe() {
        assertThat(CrewFavorService.isMe(null, 4_211L)).isFalse();
    }

    private static User userWith(Long id) {
        return User.builder().id(id).build();
    }
}

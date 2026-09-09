package com.heattrip.heat_trip_backend.user;

import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * "이 id 의 사람" 을 꺼내는 것. <b>{@code user} 모듈의 공개 표면이다.</b> (이슈 #418)
 *
 * <h2>왜 이 타입이 있어야 하는가</h2>
 * <p>일정({@code schedule})에는 <b>담당자</b>가 있다 — "토요일 보리 병원, 아빠". 그 담당자는
 * 지금 로그인한 사람이 아니라 <b>남</b>이라, {@code @CurrentUser} 로 받을 수 없다. 그런데
 * {@code Schedule} 은 {@code @ManyToOne User} 를 <b>들어야</b> Hibernate 가
 * {@code fk_schedule_assignee} 를 만든다({@code DogOwnership.requireMineEntity} 가 같은
 * 이유로 행을 돌려준다). 그래서 행이 필요하다.
 *
 * <p>그렇다고 {@code schedule} 이 {@code user.repository.UserRepository} 를 직접 부르면
 * 안 된다 — 규약이 이렇게 적어 뒀다
 * ({@code docs/02-architecture/backend-implementation-guide.md} §2.3).
 *
 * <blockquote>
 * 리포지토리를 남이 직접 부르는 것은 공용 어휘가 아니라 <b>그냥 새는 것</b>이다.
 * </blockquote>
 *
 * <p>{@link WithdrawnUsers} 가 "이 id 들이 아직 있는가" 에 답하는 것과 같은 자리다. 패키지
 * 루트라 그 자체로 공개 표면이고 별도 선언이 필요 없다(#105 · #108).
 *
 * <h2>읽기만 연다</h2>
 * <p>{@code save}·{@code delete} 를 여기 두지 않는다. 리포지토리를 통째로 열면 다음 사람이
 * 일정 코드에서 사용자를 <b>고칠</b> 수도 있게 된다 — {@link WithdrawnUsers} 와
 * {@code DogOwnership} 이 경계한 것이 정확히 그것이다.
 *
 * <h2>권한은 여기서 안 본다</h2>
 * <p>이 표면은 "그 행이 있는가" 에만 답한다. "그 사람을 담당자로 붙여도 되는가" 는 부르는
 * 쪽의 질문이다 — 일정은 그것을 <b>주인 멤버십</b>으로 답하고({@code ScheduleService}),
 * 그 규칙은 {@code user} 가 알 수 있는 것이 아니다.
 */
@Component
public class KnownUsers {

    private final UserRepository users;

    public KnownUsers(UserRepository users) {
        this.users = users;
    }

    /**
     * 이 id 의 사람.
     *
     * @param userId {@code null} 이면 <b>빈 값</b>이다. 부르는 쪽이 "안 보냈다" 를 따로
     *               다루지 않아도 되게 한다
     * @return 없거나 탈퇴했으면 빈 값
     */
    public Optional<User> byId(Long userId) {
        return userId == null ? Optional.empty() : users.findById(userId);
    }
}

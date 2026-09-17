package com.heattrip.heat_trip_backend.user.signup;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 틀린 시도를 <b>따로 커밋한다</b> — 이슈 #635.
 *
 * <h2>왜 빈이 하나 더 필요한가</h2>
 * <p>{@code EmailVerificationService.verify} 는 코드가 틀리면 401 을 던진다. 그 메서드가
 * {@code @Transactional} 이므로 <b>던지는 순간 그 트랜잭션이 통째로 롤백된다</b> — 같은 안에서
 * 올린 시도 횟수도 함께 사라진다.
 *
 * <p>그러면 {@code attempts} 는 영원히 0 이고 무차별 시도를 막는 장치가 <b>있는 척만</b> 한다.
 * 실제로 그랬다 — 다섯 번 틀린 뒤에도 맞는 코드가 통과했고, 통합 테스트가 그것을 잡았다.
 *
 * <p>자기 호출은 프록시를 안 지나므로 {@code REQUIRES_NEW} 를 같은 클래스 안에 둘 수 없다.
 * 그래서 빈을 나눈다.
 */
@Component
public class PendingSignupAttempts {

    private final PendingSignupRepository pending;

    public PendingSignupAttempts(PendingSignupRepository pending) {
        this.pending = pending;
    }

    /**
     * 한 번 틀렸다고 적는다. <b>바깥 트랜잭션이 롤백돼도 이 값은 남는다.</b>
     *
     * @return 이 시도까지 포함한 누적 횟수
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public int recordFailure(Long id) {
        PendingSignup row = pending.findById(id).orElse(null);
        if (row == null) {
            return 0;
        }
        row.setAttempts(row.getAttempts() + 1);
        pending.saveAndFlush(row);
        return row.getAttempts();
    }

    /**
     * 죽은 대기 행을 지운다. 이것도 따로 커밋한다 — 410 을 던지면서 지워야 하기 때문이다.
     *
     * <p>안 지우면 만료·시도초과 상태의 행이 남아 {@code UNIQUE(email)} 를 잡는다. 그 사람은
     * 다시 가입하려 해도 옛 행을 덮어쓰는 길밖에 없는데, 그 판단을 여기서 하지 않는다 —
     * 죽었으면 지운다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void discard(Long id) {
        pending.findById(id).ifPresent(pending::delete);
    }
}

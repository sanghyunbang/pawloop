package com.heattrip.heat_trip_backend.user.signup;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.heattrip.heat_trip_backend.user.UserTime;

/**
 * 만료된 가입 대기 행을 야간에 지운다 — 이슈 #635.
 *
 * <h2>안 지우면 개인정보가 쌓인다</h2>
 *
 * <p>대기 행에는 이메일 주소와 <b>비밀번호 해시</b>가 들어 있다. 코드를 안 넣고 만 사람의
 * 행은 십 분 뒤부터 <b>쓸 일이 없는데</b>, 안 지우면 영영 남는다. 필요 이상으로 보관하지
 * 않는다는 처리방침과도 어긋난다.
 *
 * <p>인증 흐름은 만료된 행을 <b>덮어쓰기만</b> 한다({@code EmailVerificationService.start}) —
 * 같은 주소로 다시 시도하는 사람의 것만 정리되고, 다시 안 오는 사람의 것은 그대로다.
 * 그래서 시간이 지우는 자리가 따로 필요하다.
 *
 * <p>{@code RefreshTokenPurgeScheduler} 와 같은 모양이다 — 시각만 여기서 정하고 지우는 일은
 * 저장소가 한다. 주기를 설정으로 뺀 이유도 같다: 운영에서 시각을 옮기거나 잠시 끌 수 있어야
 * 하고, 하드코딩하면 그때마다 배포가 필요하다.
 */
@Component
public class PendingSignupPurgeScheduler {

    private static final Logger log = LoggerFactory.getLogger(PendingSignupPurgeScheduler.class);

    private final PendingSignupRepository pending;

    public PendingSignupPurgeScheduler(PendingSignupRepository pending) {
        this.pending = pending;
    }

    /** refresh 토큰 정리(4:30)와 겹치지 않게 십 분 뒤다. */
    @Scheduled(cron = "${app.mail.pending-purge-cron:0 40 4 * * *}", zone = "Asia/Seoul")
    @Transactional
    public void purgeExpiredPendingSignups() {
        int removed = pending.deleteExpired(UserTime.nowUtc());
        if (removed > 0) {
            log.info("만료된 가입 대기 {}건을 지웠다", removed);
        }
    }
}

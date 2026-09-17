package com.heattrip.heat_trip_backend.user.verification;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.heattrip.heat_trip_backend.user.UserTime;

import java.util.List;

/**
 * 만료된 인증 행을 야간에 지운다 — 이슈 #635.
 *
 * <h2>왜 목록으로 받나</h2>
 *
 * <p>표마다 스케줄러를 하나씩 두면 두 번째 표를 만드는 날 그것을 잊는다. 그리고 그 고장은
 * "개인정보가 안 지워진다" 라서 화면 어디에도 안 나타난다 — 아무도 못 본다.
 *
 * <p>{@link ExpiringRows} 를 구현한 빈을 전부 돌면, 새 표는 인터페이스를 붙이는 것만으로
 * 정리에 들어온다.
 *
 * <p>{@code RefreshTokenPurgeScheduler} 와 같은 모양이다 — 시각만 여기서 정하고 지우는 일은
 * 저장소가 한다. 주기를 설정으로 뺀 이유도 같다: 운영에서 시각을 옮기거나 잠시 끌 수 있어야
 * 하고, 하드코딩하면 그때마다 배포가 필요하다.
 */
@Component
public class VerificationPurgeScheduler {

    private static final Logger log = LoggerFactory.getLogger(VerificationPurgeScheduler.class);

    private final List<ExpiringRows> stores;

    public VerificationPurgeScheduler(List<ExpiringRows> stores) {
        this.stores = stores;
    }

    /** refresh 토큰 정리(4:30)와 겹치지 않게 십 분 뒤다. */
    @Scheduled(cron = "${app.mail.pending-purge-cron:0 40 4 * * *}", zone = "Asia/Seoul")
    @Transactional
    public void purgeExpired() {
        for (ExpiringRows store : stores) {
            int removed = store.deleteExpired(UserTime.nowUtc());
            if (removed > 0) {
                log.info("만료된 {} {}건을 지웠다", store.rowName(), removed);
            }
        }
    }

    /** 검사가 "정리에 들어온 표가 몇 개인가" 를 셀 수 있게. */
    public List<String> purgedRowNames() {
        return stores.stream().map(ExpiringRows::rowName).sorted().toList();
    }
}

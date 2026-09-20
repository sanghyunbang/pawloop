package com.heattrip.heat_trip_backend.user.service;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 동의 없는 계정 청소의 시각을 정한다 — 이슈 #660 완료 조건 4.
 *
 * <p>여기는 시각만 정한다. 무엇을 어떻게 지우는지는 {@link UnconsentedAccountSweeper} 가 안다 —
 * {@code RefreshTokenPurgeScheduler} 와 같은 나눔이다. 주기를 설정으로 뺀 이유도 같다:
 * 운영에서 시각을 옮기거나 잠시 끌 수 있어야 하고, 하드코딩하면 그때마다 배포가 필요하다.
 *
 * <h2>새벽 4:50 인 이유</h2>
 * <p>미디어 고아 정리(4:10) · refresh 토큰 정리(4:30) · 가입 대기 정리와 카탈로그 예열(4:40)
 * 뒤다. 같은 시각에 겹쳐 봐야 서로 잠금을 다툴 뿐이다.
 *
 * <h2>프로퍼티로 빈 자체를 끈다 — 기본은 켬</h2>
 * <p>{@code app.consent.cleanup.enabled=false} 면 이 클래스가 컨텍스트에 없다.
 * {@code @Scheduled} 만 조건부로 두면 빈은 뜨고 잡만 안 걸리는데 그 상태를 테스트로 재기가
 * 어렵다 — 빈의 유무는 잴 수 있다({@code PlaceCatalogWarmupScheduler} 가 같은 모양이다).
 *
 * <p>{@code matchIfMissing = true} 인 것은 그 잡과 <b>반대</b>다. 그쪽은 외부 예산을 태우는 잡이라
 * "빠진 것은 끔" 이 맞고, 이쪽은 개인정보를 거두는 잡이라 <b>빠뜨렸다고 조용히 안 도는 쪽이 더
 * 나쁘다</b>. 테스트 프로파일은 {@code application-test.properties} 에서 명시적으로 끈다 —
 * 계정을 지우는 잡이 CI 의 시드를 건드리면 안 된다.
 */
@Component
@ConditionalOnProperty(prefix = "app.consent.cleanup", name = "enabled", havingValue = "true",
        matchIfMissing = true)
public class UnconsentedAccountSweepScheduler {

    private final UnconsentedAccountSweeper sweeper;

    public UnconsentedAccountSweepScheduler(UnconsentedAccountSweeper sweeper) {
        this.sweeper = sweeper;
    }

    @Scheduled(cron = "${app.consent.cleanup.cron:0 50 4 * * *}", zone = "Asia/Seoul")
    public void sweepUnconsentedAccounts() {
        sweeper.sweep();
    }
}

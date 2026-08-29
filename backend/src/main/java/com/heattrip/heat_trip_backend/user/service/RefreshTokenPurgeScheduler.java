package com.heattrip.heat_trip_backend.user.service;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 만료된 refresh 토큰 행을 야간에 일괄 삭제한다. (이슈 #9)
 *
 * <p>정리 자체는 {@link RefreshTokenService#purgeExpired()} 가 하고 이 클래스는 시각만 정한다.
 * 그래야 정리 로직을 벽시계 없이(고정 {@code Clock}) 단위 테스트할 수 있고, 여기는 위임
 * 한 줄이라 {@code verify} 로 충분해진다.
 *
 * <p>주기를 설정으로 뺀 이유: 운영에서 시각을 옮기거나(부하가 겹칠 때) 잠시 끌 수 있어야 한다.
 * 하드코딩하면 그때마다 배포가 필요하다.
 */
@Component
public class RefreshTokenPurgeScheduler {

    private final RefreshTokenService refreshTokenService;

    public RefreshTokenPurgeScheduler(RefreshTokenService refreshTokenService) {
        this.refreshTokenService = refreshTokenService;
    }

    @Scheduled(cron = "${auth.refresh-token.purge-cron:0 30 4 * * *}", zone = "Asia/Seoul")
    public void purgeExpiredRefreshTokens() {
        refreshTokenService.purgeExpired();
    }
}

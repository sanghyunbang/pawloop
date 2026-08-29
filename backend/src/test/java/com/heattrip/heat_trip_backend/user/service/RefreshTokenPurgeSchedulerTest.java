package com.heattrip.heat_trip_backend.user.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.scheduling.annotation.Scheduled;

import java.lang.reflect.Method;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/**
 * 만료 정리 잡이 실제로 등록될 모양인지 확인한다 — 이슈 #9.
 *
 * <p>스케줄러 자체는 위임 한 줄이라 {@code verify} 로 충분하다. 정리 규칙(무엇을 지우는가)은
 * {@link RefreshTokenServiceTest} 가 고정 시계로 잠근다 — 여기서 벽시계를 기다리지 않는다.
 *
 * <p>cron 표현식을 문자열로 확인하는 이유: 잡이 존재해도 표현식이 사라지거나 하드코딩으로
 * 돌아가면 운영에서 시각을 옮길 수 없다. 그리고 {@code zone} 이 빠지면 서버 타임존에 따라
 * 실행 시각이 조용히 달라진다.
 */
class RefreshTokenPurgeSchedulerTest {

    @Test
    @DisplayName("스케줄 잡은 정리 로직을 서비스에 그대로 위임한다")
    void scheduledJob_delegatesToTheService() {
        RefreshTokenService refreshTokenService = mock(RefreshTokenService.class);

        new RefreshTokenPurgeScheduler(refreshTokenService).purgeExpiredRefreshTokens();

        verify(refreshTokenService).purgeExpired();
    }

    @Test
    @DisplayName("실행 주기는 설정으로 뺀 cron 이고 타임존이 Asia/Seoul 로 고정돼 있다")
    void scheduledJob_readsCronFromConfiguration() throws Exception {
        Method job = RefreshTokenPurgeScheduler.class.getMethod("purgeExpiredRefreshTokens");
        Scheduled scheduled = job.getAnnotation(Scheduled.class);

        assertThat(scheduled)
                .as("애너테이션이 사라지면 만료 행이 영원히 쌓인다 — 그래도 앱은 멀쩡히 뜬다")
                .isNotNull();
        assertThat(scheduled.cron())
                .as("운영에서 시각을 옮기거나 끌 수 있어야 한다")
                .isEqualTo("${auth.refresh-token.purge-cron:0 30 4 * * *}");
        assertThat(scheduled.zone())
                .as("zone 이 없으면 서버 타임존에 따라 실행 시각이 조용히 달라진다")
                .isEqualTo("Asia/Seoul");
    }
}

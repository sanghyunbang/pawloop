package com.heattrip.heat_trip_backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

/**
 * 시간의 주입점. (이슈 #9)
 *
 * <p>{@code LocalDateTime.now()} 를 코드에 직접 쓰면 만료 경계를 테스트로 고정할 수 없다.
 * 이슈가 "테스트하기 어려운 부분"으로 지목한 자리가 정확히 그것이다 — {@code expiresAt} 을
 * 과거로 직접 세팅하는 우회는 가능하지만, 그러면 <b>{@code jwt.refresh-expiration} 설정값이
 * 실제로 쓰였는지</b>는 영원히 검증되지 않는다.
 *
 * <p>{@code RefreshTokenService} 가 이 빈을 받아 쓰고, 테스트는 고정 {@link Clock} 을 넣어
 * "만료 시각 = 발급 시각 + 14일"과 만료 정리 경계를 벽시계 없이 단언한다.
 */
@Configuration
public class ClockConfig {

    @Bean
    public Clock clock() {
        return Clock.systemDefaultZone();
    }
}

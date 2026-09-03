package com.heattrip.heat_trip_backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

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
 *
 * <h2>존을 박는다 — 이슈 #209({@code Groups-medium-6})</h2>
 * <p>{@code systemDefaultZone()} 은 <b>배포 환경의 {@code TZ} 환경변수 하나로 조용히 바뀐다.</b>
 * 그러면 {@code CareService} 의 "오늘" 이 함께 밀린다 — KST 00:00~08:59 에 찍은 케어 기록이
 * '어제' 가 되어 <b>이중 급여 방지 화면에서 사라진다.</b> 밥을 두 번 주지 않게 하는 것이 그
 * 기능의 목적이므로, 조용히 틀리는 것이 가장 나쁘다.
 *
 * <p>{@code CareService} javadoc 이 이 답을 미리 적어 뒀다 — "서버 존을 옮기는 날의 답은
 * {@code ClockConfig} 의 빈에 존을 박는 것이고, 그러면 여기는 한 글자도 안 고쳐도 된다."
 * 실제로 그 클래스는 한 글자도 안 고쳤다.
 *
 * <p><b>인스턴트는 안 바뀐다.</b> {@code Clock.system(zone)} 은 같은 순간을 주고 존만 정한다 —
 * {@code Instant.now(clock)} 은 그대로이고 {@code LocalDateTime.now(clock)}·
 * {@code LocalDate.now(clock)} 만 이 존을 따른다. 그래서 리프레시 토큰 만료 계산은 영향이 없다.
 */
@Configuration
public class ClockConfig {

    /**
     * 서비스의 기준 존. <b>"오늘" 이 여기서 정해진다.</b>
     *
     * <p>한국 반려인을 위한 앱이라 하루 경계가 KST 다. 사용자가 해외에 있어도 "오늘의 케어" 는
     * 집의 하루를 뜻한다 — 가족이 나눠 보는 기록이기 때문이다.
     */
    public static final ZoneId SERVICE_ZONE = ZoneId.of("Asia/Seoul");

    @Bean
    public Clock clock() {
        return Clock.system(SERVICE_ZONE);
    }
}

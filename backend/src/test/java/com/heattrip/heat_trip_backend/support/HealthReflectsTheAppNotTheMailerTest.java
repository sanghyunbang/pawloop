package com.heattrip.heat_trip_backend.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.actuate.mail.MailHealthIndicator;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.core.env.Environment;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 건강 검사가 <b>앱</b>을 말하는가, 아니면 일부러 안 켠 곁다리를 말하는가 — 이슈 #640.
 *
 * <h2>무슨 일이 있었나</h2>
 *
 * <p>2026-09-17 배포 뒤 운영의 {@code /actuator/health} 가 503 · {@code DOWN} 을 답했다.
 * 그런데 {@code liveness} · {@code readiness} 는 둘 다 200 · {@code UP} 이었고
 * {@code GET /api/places/nearby} 도 200 이었다 — <b>앱은 멀쩡했다.</b> 컨테이너 로그가
 * 폴링마다 이 두 줄을 찍고 있었다.
 *
 * <pre>
 * o.s.b.actuate.mail.MailHealthIndicator : Mail health check failed
 * jakarta.mail.AuthenticationFailedException: failed to connect, no password specified?
 * </pre>
 *
 * <p>메일이 꺼져 있는 것은 <b>의도다</b> — terraform 의 {@code mail_domain_name} 을 비워 둬서
 * SES 자원이 아예 없다. {@code MailConfig} 는 그 판단을 지켜 {@code LoggingMailer} 를 고른다.
 * 지키지 못한 자리가 건강 검사기 하나였다: 스프링은 {@code JavaMailSender} 빈만 보고 켜는데,
 * {@code application.properties} 의 주석이 이미 경고해 둔 대로 <b>빈 문자열도 "속성이 있다" 로
 * 쳐서</b> 그 빈은 만들어진다. 발송은 꺼졌는데 검사기만 살아남아 영원히 실패했다.
 *
 * <h2>왜 이 검사가 있어야 하나</h2>
 *
 * <p>{@code docker-compose.yml} 의 앱 헬스체크가 부르는 주소가 바로 이 주소다. 합친 값이
 * 상수로 빨간불이면 컨테이너도 영구히 {@code unhealthy} 고, 그러면 <b>다음에 진짜로 아플 때
 * 아무도 못 알아챈다.</b> #601 이 "Up 만 찍는 표는 상태 표가 아니다" 라고 정해 놓고 만든
 * 장치가, 항상 빨간불이 되는 순간 같은 이유로 무용지물이 된다.
 *
 * <h2>이 컨텍스트가 운영과 같은 조건인 이유</h2>
 *
 * <p>따로 설정을 안 주는 것이 <b>의도다.</b> {@code application.properties} 가
 * {@code spring.mail.host=${SPRING_MAIL_HOST:}} 로 적혀 있어서, 환경변수가 없는 테스트에서도
 * 운영과 <b>똑같이</b> 빈 문자열이 된다. {@code @TestPropertySource} 로 조건을 만들어 내면
 * 재는 것이 "우리가 꾸민 상황" 이 되고, 덤으로 컨텍스트 캐시 키가 갈라져 스프링이 한 번 더
 * 뜬다(#21). 애너테이션이 두 줄뿐인 것도 같은 이유다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class HealthReflectsTheAppNotTheMailerTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ApplicationContext context;

    @Autowired
    private Environment environment;

    @Test
    @DisplayName("전제 — 이 컨텍스트에는 SMTP 자격이 없다 (운영과 같은 조건)")
    void mailIsNotConfiguredHere() {
        assertThat(environment.getProperty("spring.mail.host"))
                .as("""
                        여기에 host 가 채워져 있으면 아래 두 검사는 아무것도 안 지킨다 — \
                        메일이 꺼진 상태를 재려던 것인데 켜진 상태를 재게 된다 (#640).""")
                .isNullOrEmpty();
    }

    @Test
    @DisplayName("메일 자격이 없어도 /actuator/health 는 200 과 UP 을 답한다")
    void healthIsUpWithoutMailCredentials() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    @DisplayName("메일 건강 검사기가 아예 안 켜진다 — 위 검사가 깨졌을 때 범인을 여기서 읽는다")
    void theMailIndicatorIsNotRegistered() {
        assertThat(context.getBeanNamesForType(MailHealthIndicator.class))
                .as("""
                        management.endpoint.health.show-details=never 라 503 본문은 어느 검사기가 \
                        쓰러졌는지 말해 주지 않는다. 위 검사와 이 검사가 같이 빨간불이면 범인이 \
                        메일이라는 뜻이다 (#640).

                        메일을 진짜로 켜는 날에는 이 검사기도 같이 켜야 한다. 그때는 \
                        MANAGEMENT_HEALTH_MAIL_ENABLED=true 가 환경에 들어가므로 이 테스트가 \
                        도는 환경(자격 없음)과는 갈린다.""")
                .isEmpty();
    }
}

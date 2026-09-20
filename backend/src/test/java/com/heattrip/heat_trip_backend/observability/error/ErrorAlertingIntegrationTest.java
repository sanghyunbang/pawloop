package com.heattrip.heat_trip_backend.observability.error;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.observability.ai.SpringAiErrorSummarizer;
import com.heattrip.heat_trip_backend.observability.alert.AlertOrchestrator;
import com.heattrip.heat_trip_backend.observability.alert.AlertRateLimiter;
import com.heattrip.heat_trip_backend.observability.alert.SlackNotifier;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * 정상 상황(4xx)은 경보가 아니고, 서버 고장(5xx)은 여전히 경보다 — 이슈 #657.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@link ErrorAlertingAspect} 가 컨트롤러 예외를 잡는 순간 종류를 가리지 않고 경보를 보냈다. 가족이
 * 없는 사람의 {@code GET /api/groups/me} 는 {@code NoSuchElementException} → 404 로 <b>맞게</b> 끝나는데도
 * 새로 가입한 사람이 앱을 열 때마다 슬랙 경보와 {@code ERROR} 로그가 나갔고, 레이트 리미터가 그것을
 * 깎아내면서 진짜 오류도 함께 버릴 판이었다.
 *
 * <h2>왜 필터 체인부터 태우는가</h2>
 * <p>애스펙트만 단위로 부르면 "경보를 보냈는가" 만 보이고 "응답이 몇으로 끝났는가" 는 안 보인다. 고친
 * 규칙이 바로 그 둘의 관계(5xx 일 때만)라, {@code GlobalExceptionHandler} 가 상태를 정하고 필터가 그것을
 * 읽는 실제 경로를 그대로 지나야 한다. {@code GlobalExceptionHandlerStatusTest} 와 같은 모양이다.
 *
 * <h2>되돌리기 (#21 §4)</h2>
 * <ul>
 *   <li>{@code ErrorAlertingFilter} 의 5xx 판정을 빼면(붙여 둔 이벤트를 무조건 보내면) — 404 검사 둘이 빨개진다.</li>
 *   <li>애스펙트가 이벤트를 안 붙이면 — 500·502 검사가 빨개진다.</li>
 *   <li>필터가 5xx 를 안 보내면 — 500·502 검사가 빨개진다.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ErrorAlertingIntegrationTest extends AbstractMySqlIntegrationTest {

    /** 상태 코드만 던지는 시험용 엔드포인트. 테스트 컨텍스트에만 등록된다. */
    @RestController
    static class Probe {
        static final String BASE = "/__probe/alerting";

        /** 정상 상황 — {@code GlobalExceptionHandler} 가 404 로 옮긴다. {@code GroupController.me} 와 같은 모양. */
        @GetMapping(BASE + "/not-found")
        void notFound() {
            throw new NoSuchElementException("probe-not-found");
        }

        /** 예상하지 못한 예외 — catch-all 이 500 을 만든다. */
        @GetMapping(BASE + "/boom")
        void boom() {
            throw new IllegalStateException("probe-boom");
        }

        /** 컨트롤러가 스스로 5xx 를 골랐다 — 500 이 아니어도 서버 쪽 잘못이다. */
        @GetMapping(BASE + "/bad-gateway")
        void badGateway() {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "probe-bad-gateway");
        }
    }

    /** 경보를 보내는 대신 센다. 슬랙·GPT 는 부르지 않는다. */
    static class RecordingAlerts extends AlertOrchestrator {
        final List<ErrorEvent> events = new CopyOnWriteArrayList<>();

        RecordingAlerts(ObservabilityProperties props, AlertRateLimiter rateLimiter,
                        SpringAiErrorSummarizer summarizer, SlackNotifier slackNotifier) {
            super(props, rateLimiter, summarizer, slackNotifier);
        }

        @Override
        public void notifyError(ErrorEvent event) {
            events.add(event);
        }
    }

    @TestConfiguration
    static class Fakes {
        @Bean
        Probe alertingProbe() {
            return new Probe();
        }

        @Bean
        @Primary
        RecordingAlerts recordingAlerts(ObservabilityProperties props, AlertRateLimiter rateLimiter,
                                        SpringAiErrorSummarizer summarizer, SlackNotifier slackNotifier) {
            return new RecordingAlerts(props, rateLimiter, summarizer, slackNotifier);
        }
    }

    @Autowired private MockMvc mockMvc;
    @Autowired private RecordingAlerts alerts;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;

    @BeforeEach
    void clearAlerts() {
        alerts.events.clear();
    }

    /** 필수 약관에 동의한, 그러나 가족은 없는 사람 — 새로 가입한 사람이 정확히 이 상태다. */
    private String bearer() {
        User user = consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("alert-probe@example.com")
                .name("보리")
                .build()));
        return "Bearer " + jwtProvider.createAccessToken(user.getId(), user.getRole());
    }

    @Test
    @DisplayName("가족이 없는 사람의 GET /api/groups/me 는 404 이고 경보가 안 나간다 — 이슈의 그 요청")
    void aUserWithoutAFamilyGroup_getsNotFoundWithoutAnAlert() throws Exception {
        var response = mockMvc.perform(get("/api/groups/me").header("Authorization", bearer()))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("응답은 여전히 404 여야 한다 — 앱이 그걸로 '아직 가족이 없다' 를 판단한다(완료 조건 2)")
                .isEqualTo(404);
        assertThat(alerts.events)
                .as("가족이 없는 것은 정상이다. 경보가 나가면 새로 가입한 사람마다 슬랙이 울린다(완료 조건 1)")
                .isEmpty();
    }

    @Test
    @DisplayName("404 로 끝나는 컨트롤러 예외는 경보가 아니다 — 응답이 이미 클라이언트에게 할 말을 했다")
    void anExceptionThatEndsAsNotFound_isNotAnAlert() throws Exception {
        var response = mockMvc.perform(get(Probe.BASE + "/not-found").header("Authorization", bearer()))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(404);
        assertThat(alerts.events).isEmpty();
    }

    @Test
    @DisplayName("500 으로 끝나는 예외는 여전히 경보다 — 이 검사가 없으면 위 둘은 '아무것도 안 보낸다' 로도 초록이다")
    void anUnexpectedException_stillAlerts() throws Exception {
        var response = mockMvc.perform(get(Probe.BASE + "/boom").header("Authorization", bearer()))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(500);
        assertThat(alerts.events).as("완료 조건 3").hasSize(1);
        ErrorEvent event = alerts.events.get(0);
        assertThat(event.getExceptionClass()).isEqualTo(IllegalStateException.class.getName());
        assertThat(event.getMethod()).isEqualTo("GET");
        assertThat(event.getPath())
                .as("이벤트는 요청 컨텍스트가 살아 있을 때 만들어져야 경로가 남는다 — 필터에서 만들면 N/A 다")
                .isEqualTo(Probe.BASE + "/boom");
        assertThat(event.getCorrelationId())
                .as("슬랙에서 로그로 돌아오는 열쇠. MDC 가 정리된 뒤에 만들면 비어 있다")
                .isNotBlank();
    }

    @Test
    @DisplayName("컨트롤러가 스스로 고른 5xx(502) 도 경보다 — 500 만 세면 놓친다")
    void aDeclaredServerError_alerts() throws Exception {
        var response = mockMvc.perform(get(Probe.BASE + "/bad-gateway").header("Authorization", bearer()))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(502);
        assertThat(alerts.events).hasSize(1);
        assertThat(alerts.events.get(0).getExceptionClass())
                .isEqualTo(ResponseStatusException.class.getName());
    }
}

package com.heattrip.heat_trip_backend.chat.metrics;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 채팅 메트릭이 {@code /actuator/prometheus} 로 <b>실제로 나가는지</b> 본다. (이슈 #80 완료 조건 2)
 *
 * <p>{@code ChatMetricsTest} 는 레지스트리에 등록됐는지만 본다. 그것과 <b>스크레이프 대상으로
 * 노출되는 것</b>은 다르다 — 노출 목록에서 빠지거나 엔드포인트가 꺼져 있으면 등록은 멀쩡한 채
 * 대시보드만 빈칸이다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} <b>두 줄뿐인 것은
 * 의도다.</b> 다른 조합을 쓰면 스프링 테스트 컨텍스트 캐시 키가 갈라져 컨텍스트가 하나 더 뜬다
 * (#21). 이 저장소의 다른 통합 테스트가 쓰는 것과 같은 두 줄이라 캐시를 공유한다.
 *
 * <p>{@code AbstractMySqlIntegrationTest} 를 상속하는 것도 같은 이유다. 데이터소스가 없으면
 * 컨텍스트가 아예 안 뜬다. H2 로 대신하는 것은 #49 가 금지한다 — 그러면 초록불이 거짓말을 한다.
 *
 * <p><b>이름이 dot 에서 snake 로 바뀌는 것을 여기서 확인한다.</b> 코드에는
 * {@code chat.message.sent} 라고 적고 Prometheus 로는 {@code chat_message_sent_total} 로 나간다 —
 * 그 변환을 Micrometer 가 하므로 우리가 snake 로 적으면 안 된다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ChatMetricsExposureIntegrationTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ChatMetrics chatMetrics;

    private String scrape() throws Exception {
        return mockMvc.perform(get("/actuator/prometheus"))
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    @Test
    @DisplayName("폴링과 발급 지표는 첫 호출 전에도 스크레이프에 나온다")
    void pollAndSeqAssignAreExposedBeforeAnyTraffic() throws Exception {
        String body = scrape();

        assertThat(body)
                .as("""
                        chat.poll 은 생성자에서 미리 등록한다. 지표가 없는 것과 0인 것은 다르고,
                        없으면 사람이 "아직 아무도 안 썼나" 와 "계측이 깨졌나" 를 구분하지 못한다.
                        """)
                .contains("chat_poll_total")
                .contains("result=\"empty\"")
                .contains("result=\"hit\"");

        assertThat(body)
                .as("방 단위 직렬화 지점. 경합이 보이는 유일한 자리다")
                .contains("chat_seq_assign_seconds");
    }

    @Test
    @DisplayName("메시지 지표는 room_kind 태그와 함께 나온다")
    void messageSentIsExposedWithItsTag() throws Exception {
        // chat 은 originKind 를 해석하지 않는다(ADR-0011). 그래서 이 지표는 값이 들어와야
        // 시계열이 생긴다 — 방 종류를 메트릭 쪽에 미리 박으면 그 결정을 뒤집는 것이다.
        chatMetrics.messageSent("FAMILY");

        assertThat(scrape())
                .as("""
                        코드에는 chat.message.sent 라고 적었는데 여기서는 chat_message_sent_total 이어야
                        한다. 그 변환은 Micrometer 가 한다 — 우리가 snake 로 적으면 변환이 두 번 일어난다.
                        """)
                .contains("chat_message_sent_total")
                .contains("room_kind=\"FAMILY\"");
    }
}

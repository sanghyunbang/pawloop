package com.heattrip.heat_trip_backend.config;

import org.apache.catalina.connector.Connector;
import org.apache.coyote.AbstractProtocol;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 운영자 통로의 판정 — 이슈 #718. 왜 토큰이 아니라 들어온 커넥터로 가르는지는 {@link OperatorChannel} 에 있다.
 *
 * <p>스프링을 띄우지 않는다. 이 클래스가 답하는 것은 "이 요청이 운영자 커넥터로 왔는가" 하나라서 그 판정만 잰다.
 * 그 판정이 실제 보안 규칙에 물려 있는지는 {@code OperatorModerationIntegrationTest}, 커넥터가 실제로 루프백에만
 * 묶이는지는 {@code OperatorConnectorBindingTest} 가 잰다.
 */
class OperatorChannelTest {

    @Test
    @DisplayName("꺼져 있으면(0) 어떤 요청도 운영자 요청이 아니다 — 로컬 포트가 0 인 가짜 요청이어도")
    void disabledChannelCarriesNothing() {
        OperatorChannel channel = new OperatorChannel(0, 8080);

        assertThat(channel.enabled()).isFalse();
        assertThat(channel.carries(requestOnLocalPort(0)))
                .as("커넥터가 없는데 '로컬 포트 0 == 포트 0' 으로 통과하면 꺼 둔 통로가 열린다")
                .isFalse();
    }

    @Test
    @DisplayName("켜져 있으면 그 포트로 들어온 요청만 운영자 요청이다")
    void enabledChannelCarriesOnlyItsOwnPort() {
        OperatorChannel channel = new OperatorChannel(9091, 8080);

        assertThat(channel.carries(requestOnLocalPort(9091))).isTrue();
        assertThat(channel.carries(requestOnLocalPort(8080))).as("본 커넥터로 온 요청").isFalse();
    }

    @Test
    @DisplayName("본 포트와 같거나 범위를 벗어난 값이면 서버가 뜨지 않는다")
    void badPortsStopTheBoot() {
        assertThatThrownBy(() -> new OperatorChannel(8080, 8080))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("server.port");
        assertThatThrownBy(() -> new OperatorChannel(-1, 8080)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new OperatorChannel(65_536, 8080)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    @DisplayName("운영자 커넥터는 127.0.0.1 에만 묶인다 — 모든 주소(0.0.0.0)에 열리면 컨테이너 밖에서 닿는다")
    void connectorIsBoundToLoopbackOnly() {
        Connector connector = OperatorChannelConfig.loopbackConnector(19_091);

        assertThat(connector.getPort()).isEqualTo(19_091);
        AbstractProtocol<?> protocol = (AbstractProtocol<?>) connector.getProtocolHandler();
        assertThat(protocol.getAddress()).as("주소를 안 정하면 Tomcat 은 모든 주소에 연다").isNotNull();
        assertThat(protocol.getAddress().getHostAddress()).isEqualTo("127.0.0.1");
    }

    private static MockHttpServletRequest requestOnLocalPort(int port) {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/internal/moderation/reports/1");
        request.setLocalPort(port);
        return request;
    }
}

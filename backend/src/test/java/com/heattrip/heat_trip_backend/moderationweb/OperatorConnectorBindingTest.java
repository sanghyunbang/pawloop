package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.apache.catalina.connector.Connector;
import org.apache.coyote.AbstractProtocol;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.web.embedded.tomcat.TomcatWebServer;
import org.springframework.boot.web.servlet.context.ServletWebServerApplicationContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.ServerSocket;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 진짜 서버를 띄워 <b>진짜 포트</b>로 잰다 — 이슈 #718.
 *
 * <p>{@code OperatorModerationIntegrationTest} 는 가짜 요청의 로컬 포트로 판정만 잰다. 그것만으로는 두 가지를
 * 모른다 — 운영자 커넥터가 정말 열리는지, 그리고 <b>루프백에만</b> 묶이는지. 모든 주소(0.0.0.0)에 열린 운영자
 * 커넥터는 이 설계에서 가장 나쁜 실패라서, 실제 Tomcat 의 커넥터를 꺼내 주소를 본다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OperatorConnectorBindingTest extends AbstractMySqlIntegrationTest {

    private static final int OPERATOR_PORT = freePort();

    @DynamicPropertySource
    static void operatorPort(DynamicPropertyRegistry registry) {
        registry.add("app.operator.port", () -> OPERATOR_PORT);
    }

    @LocalServerPort private int serverPort;
    @Autowired private ServletWebServerApplicationContext context;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    @DisplayName("운영자 커넥터가 실제로 열리고, 주소는 127.0.0.1 이다")
    void operatorConnectorIsOpenOnLoopbackOnly() {
        TomcatWebServer server = (TomcatWebServer) context.getWebServer();
        Connector operator = Arrays.stream(server.getTomcat().getService().findConnectors())
                .filter(c -> c.getPort() == OPERATOR_PORT)
                .findFirst()
                .orElseThrow(() -> new AssertionError("운영자 커넥터가 없다 — 포트 " + OPERATOR_PORT));

        AbstractProtocol<?> protocol = (AbstractProtocol<?>) operator.getProtocolHandler();
        assertThat(protocol.getAddress()).as("주소를 안 정하면 모든 주소에 열린다").isNotNull();
        assertThat(protocol.getAddress().getHostAddress()).isEqualTo("127.0.0.1");
    }

    @Test
    @DisplayName("같은 요청이 운영자 포트로는 통과하고(없는 신고라 404), 본 포트로는 401 이다")
    void sameRequestPassesOnlyOnTheOperatorPort() throws Exception {
        String path = "/internal/moderation/reports/987654321";

        assertThat(statusOf("http://127.0.0.1:" + OPERATOR_PORT + path))
                .as("보안을 지나 컨트롤러까지 갔다 — 없는 번호라 404")
                .isEqualTo(404);
        assertThat(statusOf("http://127.0.0.1:" + serverPort + path))
                .as("본 포트에서는 토큰이 없으니 401")
                .isEqualTo(401);
    }

    private int statusOf(String url) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create(url)).GET().build(), HttpResponse.BodyHandlers.discarding())
                .statusCode();
    }

    private static int freePort() {
        try (ServerSocket socket = new ServerSocket(0)) {
            return socket.getLocalPort();
        } catch (IOException e) {
            throw new UncheckedIOException("빈 포트를 못 찾았다", e);
        }
    }
}

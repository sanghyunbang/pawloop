package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;

import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 슬랙이 굳어도 우리는 안 굳는다 — 이슈 #707 §3.
 *
 * <h2>왜 이 검사가 있나</h2>
 * <p>고치기 전의 {@code SlackNotifier} 는 맨 {@code WebClient} 로 인자 없는 {@code block()} 을
 * 불렀다 — 타임아웃이 <b>한 겹도</b> 없었다. 슬랙이 꺼져 있어 I/O 전에 빠지니 안 터졌을 뿐,
 * 켜는 순간 에러 알림은 실패한 그 요청 스레드를, 신고 알림은 실행기 스레드를 영원히 잡을 수
 * 있었다.
 *
 * <h2>어떻게 재나</h2>
 * <p>연결은 받아 주고 <b>응답은 영원히 안 하는</b> 서버를 이 JVM 안에 띄운다({@link ServerSocket}).
 * 가짜 슬랙 라이브러리가 필요 없고 네트워크 밖으로 안 나간다. 타임아웃을 0.3초로 두고, 호출이
 * 2초 안에 <b>거짓</b>으로 돌아오면 통과다.
 *
 * <p>되돌리기: {@code SlackNotifier.withTimeouts} 가 {@code responseTimeout} 을 안 걸면 이 검사는
 * 2초를 넘겨 실패한다(실제로는 JUnit 이 끝나지 않는다).
 */
class SlackNotifierTimeoutTest {

    private ServerSocket blackHole;
    private final List<Socket> accepted = new ArrayList<>();
    private Thread acceptor;

    @BeforeEach
    void openABlackHole() throws IOException {
        blackHole = new ServerSocket(0, 8, InetAddress.getLoopbackAddress());
        acceptor = new Thread(() -> {
            try {
                while (!blackHole.isClosed()) {
                    accepted.add(blackHole.accept());   // 받기만 하고 한 바이트도 안 돌려준다
                }
            } catch (IOException ignored) {
                // 닫힐 때 난다
            }
        }, "black-hole-acceptor");
        acceptor.setDaemon(true);
        acceptor.start();
    }

    @AfterEach
    void closeIt() throws IOException {
        for (Socket s : accepted) {
            s.close();
        }
        blackHole.close();
    }

    @Test
    @DisplayName("응답이 영원히 안 오면 정해진 시간 안에 거짓으로 돌아온다 — 스레드를 잡아 두지 않는다")
    void aHangingSlackDoesNotHangUs() {
        String url = "http://127.0.0.1:" + blackHole.getLocalPort() + "/hook";
        ObservabilityProperties props = new ObservabilityProperties();
        props.getSlack().setEnabled(true);
        props.getSlack().setWebhookUrl(url);
        props.getSlack().setReportWebhookUrl(url);
        props.getSlack().setConnectTimeoutMs(300);
        props.getSlack().setReadTimeoutMs(300);
        SlackNotifier notifier = new SlackNotifier(WebClient.builder(), props);

        long started = System.nanoTime();
        boolean errorSent = notifier.send("에러 알림");
        boolean reportSent = notifier.sendReport("신고 알림");
        Duration elapsed = Duration.ofNanos(System.nanoTime() - started);

        assertThat(errorSent).as("응답이 없었으니 성공일 수 없다").isFalse();
        assertThat(reportSent).isFalse();
        assertThat(elapsed)
                .as("두 호출 합쳐 2초를 넘겼다면 타임아웃이 안 걸린 것이다 (설정은 0.3초)")
                .isLessThan(Duration.ofSeconds(2));
        assertThat(accepted).as("연결 자체는 됐어야 한다 — 안 됐으면 타임아웃이 아니라 연결 실패를 잰 것이다")
                .isNotEmpty();
    }
}

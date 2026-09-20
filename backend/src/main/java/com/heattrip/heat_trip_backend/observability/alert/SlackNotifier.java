package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;

import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import io.netty.handler.timeout.WriteTimeoutHandler;

import lombok.extern.slf4j.Slf4j;

import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * 슬랙 웹훅으로 보낸다.
 *
 * <h2>타임아웃이 걸려 있다 — 이슈 #707 §3</h2>
 * <p>예전에는 자동설정된 맨 {@code WebClient.Builder} 를 그대로 {@code build()} 해서
 * 인자 없는 {@code block()} 을 불렀다. <b>한 겹도 안 걸려 있었다.</b> 슬랙이 꺼져 있어 I/O 전에
 * 빠지니 안 터졌을 뿐, 켜는 순간 {@code ErrorAlertingAspect} 가 잡는 모든 500 이 무한 대기를
 * 탈 수 있었다. 연결·응답·읽기·쓰기 넷에 건다 — {@code KtoWebClientConfig} 와 같은 모양이다.
 *
 * <h2>두 갈래 — 에러와 신고</h2>
 * <p>{@link #send} 는 에러 알림이고 {@code slack.enabled} 와 기본 웹훅을 본다.
 * {@link #sendReport} 는 신고 알림이고 <b>전용 웹훅만</b> 본다 — 채널을 가르기 위해서다.
 * 둘은 스위치가 독립이다: 신고 알림을 켜도 에러 알림이 한 건도 안 늘고, 그 반대도 같다.
 */
@Slf4j
@Component
public class SlackNotifier {

    private final ObservabilityProperties props;
    private final WebClient client;

    public SlackNotifier(WebClient.Builder webClientBuilder, ObservabilityProperties props) {
        this.props = props;
        this.client = withTimeouts(webClientBuilder, props.getSlack()).build();
    }

    /** 에러 알림. {@code observability.slack.enabled} 와 기본 웹훅을 본다. */
    public boolean send(String text) {
        var slack = props.getSlack();
        if (!slack.isEnabled()) {
            return false;
        }
        if (isBlank(slack.getWebhookUrl())) {
            log.warn("[SLACK] webhook url is empty");
            return false;
        }
        return post(slack.getWebhookUrl(), text, slack.getChannel());
    }

    /**
     * 신고 알림 — 이슈 #707. <b>전용 웹훅이 비어 있으면 안 보낸다</b>({@code slack.enabled} 와 무관).
     *
     * <p>채널 이름을 안 싣는다. 웹훅 URL 이 이미 채널에 묶여 있고, 여기에 기본 채널
     * ({@code #backend-alerts})을 실으면 슬랙이 그쪽으로 덮어써서 갈라 둔 의미가 사라진다.
     */
    public boolean sendReport(String text) {
        String url = props.getSlack().getReportWebhookUrl();
        if (isBlank(url)) {
            return false;
        }
        return post(url, text, null);
    }

    private boolean post(String url, String text, String channel) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("text", text);
        payload.put("username", props.getSlack().getUsername());
        if (channel != null) {
            payload.put("channel", channel);
        }
        try {
            client.post()
                    .uri(url)
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(payload)
                    .retrieve()
                    .toBodilessEntity()
                    .block(Duration.ofMillis(props.getSlack().getReadTimeoutMs() + 1_000L));
            return true;
        } catch (Exception e) {
            // 본문을 안 찍는다 — 신고 알림이면 거기에 글쓴이 이름과 본문 앞부분이 있다.
            log.error("[SLACK] send failed: {}", e.toString());
            return false;
        }
    }

    private static WebClient.Builder withTimeouts(WebClient.Builder builder,
                                                  ObservabilityProperties.Slack slack) {
        int connect = slack.getConnectTimeoutMs();
        int read = slack.getReadTimeoutMs();
        HttpClient http = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, connect)
                .responseTimeout(Duration.ofMillis(read))
                .doOnConnected(conn -> conn
                        .addHandlerLast(new ReadTimeoutHandler(read, TimeUnit.MILLISECONDS))
                        .addHandlerLast(new WriteTimeoutHandler(read, TimeUnit.MILLISECONDS)));
        return builder.clientConnector(new ReactorClientHttpConnector(http));
    }

    private static boolean isBlank(String s) {
        return s == null || s.isBlank();
    }
}

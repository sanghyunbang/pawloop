package com.heattrip.heat_trip_backend.observability.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Getter
@Setter
@ConfigurationProperties(prefix = "observability")
public class ObservabilityProperties {

    private boolean enabled = true;
    private String serviceName = "heat-trip-backend";
    private int stacktraceLines = 25;
    private boolean requestLogEnabled = true;

    private RateLimit rateLimit = new RateLimit();
    private Slack slack = new Slack();
    private OpenAi openai = new OpenAi();

    @Getter
    @Setter
    public static class RateLimit {
        private boolean enabled = true;
        private long windowSeconds = 300;
    }

    @Getter
    @Setter
    public static class Slack {
        private boolean enabled = false;
        private String webhookUrl;
        private String channel = "#backend-alerts";
        private String username = "heat-trip-alert-bot";

        /**
         * 신고 알림 전용 웹훅 — 이슈 #707.
         *
         * <p>에러 알림과 <b>다른 URL</b> 이어야 한다. 슬랙 웹훅은 URL 자체가 채널에 묶이므로
         * 이것 하나로 채널이 갈리고 폰 알림도 갈린다. 같은 채널로 보내면 신고가 500 더미에
         * 묻히고, 신고 본문·양쪽 user id 가 에러 채널에 떨어진다.
         *
         * <p>이 값이 비면 신고 알림만 꺼진다 — {@link #enabled} 와 <b>무관하다.</b> 그래서
         * 에러 알림을 안 켠 채로 신고 알림만 켤 수 있다.
         */
        private String reportWebhookUrl;

        /**
         * 슬랙 HTTP 호출의 타임아웃(ms). <b>없으면 무한 대기다</b> — 슬랙이 굳는 순간 그것을
         * 부른 요청 스레드(에러 알림은 실패한 그 요청, 신고 알림은 실행기 스레드)가 같이 굳는다.
         * 공공데이터 쪽({@code KtoWebClientConfig})이 같은 이유로 거는 값과 같은 모양이다.
         */
        private int connectTimeoutMs = 3_000;
        private int readTimeoutMs = 5_000;
    }

    @Getter
    @Setter
    public static class OpenAi {
        private boolean enabled = true;
    }
}

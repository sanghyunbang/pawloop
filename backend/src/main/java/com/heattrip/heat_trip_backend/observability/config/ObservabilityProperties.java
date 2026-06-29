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
    }

    @Getter
    @Setter
    public static class OpenAi {
        private boolean enabled = true;
    }
}

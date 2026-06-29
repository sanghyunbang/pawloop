package com.heattrip.heat_trip_backend.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Getter
@Setter
@ConfigurationProperties(prefix = "app.security")
public class PublicSecurityProperties {

    private boolean docsPublic = false;
    private String allowedOrigins = "http://localhost:8080,http://10.0.2.2:8080";
    private RateLimit rateLimit = new RateLimit();

    @Getter
    @Setter
    public static class RateLimit {
        private boolean enabled = true;
        private String ipHeader = "X-Forwarded-For";
        private long windowSeconds = 60;
        private int loginMaxRequests = 10;
        private int curationMaxRequests = 30;
        private int uploadMaxRequests = 20;
        private int feedbackMaxRequests = 30;
        private int searchMaxRequests = 120;
    }
}

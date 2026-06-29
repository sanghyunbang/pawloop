package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
@RequiredArgsConstructor
public class AlertRateLimiter {

    private final ObservabilityProperties props;
    private final Map<String, Instant> lastSent = new ConcurrentHashMap<>();

    public boolean shouldSend(String fingerprint) {
        if (!props.getRateLimit().isEnabled()) {
            return true;
        }
        Instant now = Instant.now();
        Instant prev = lastSent.get(fingerprint);
        long window = props.getRateLimit().getWindowSeconds();

        if (prev != null && prev.plusSeconds(window).isAfter(now)) {
            return false;
        }

        lastSent.put(fingerprint, now);
        return true;
    }
}

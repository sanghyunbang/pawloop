package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class SlackNotifier {

    private final WebClient.Builder webClientBuilder;
    private final ObservabilityProperties props;

    public boolean send(String text) {
        var slack = props.getSlack();
        if (!slack.isEnabled()) {
            return false;
        }
        if (slack.getWebhookUrl() == null || slack.getWebhookUrl().isBlank()) {
            log.warn("[SLACK] webhook url is empty");
            return false;
        }

        Map<String, Object> payload = new HashMap<>();
        payload.put("text", text);
        payload.put("username", slack.getUsername());
        payload.put("channel", slack.getChannel());

        try {
            webClientBuilder.build()
                    .post()
                    .uri(slack.getWebhookUrl())
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(payload)
                    .retrieve()
                    .toBodilessEntity()
                    .block();
            return true;
        } catch (Exception e) {
            log.error("[SLACK] send failed: {}", e.toString());
            return false;
        }
    }
}

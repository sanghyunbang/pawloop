// src/main/java/.../llm/RecommenderHealthChecker.java
package com.heattrip.heat_trip_backend.llm;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.transport.logging.AdvancedByteBufFormat;

@Slf4j
@Component
@RequiredArgsConstructor
public class RecommenderHealthChecker {

    private final WebClient llmWebClient;

    @Value("${llm.recommender.base-url}")
    private String baseUrl;

    @EventListener(ApplicationReadyEvent.class)
    public void check() {
        try {
            String res = llmWebClient.get()
                    .uri("/health")
                    .retrieve()
                    .bodyToMono(String.class)
                    .block();
            log.info("[LLM] health ok: baseUrl={}, response={}", baseUrl, res);
        } catch (Exception e) {
            log.error("[LLM] health FAILED: baseUrl={}, err={}", baseUrl, e.toString());
        }
    }
}

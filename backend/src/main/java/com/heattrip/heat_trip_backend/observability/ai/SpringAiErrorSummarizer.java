package com.heattrip.heat_trip_backend.observability.ai;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.observability.error.ErrorEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Slf4j
@Component
@RequiredArgsConstructor
public class SpringAiErrorSummarizer {

    private final ObjectProvider<ChatClient.Builder> chatClientBuilderProvider;
    private final ObservabilityProperties props;

    public Optional<String> summarize(ErrorEvent event) {
        if (!props.getOpenai().isEnabled()) {
            return Optional.empty();
        }

        ChatClient.Builder chatClientBuilder = chatClientBuilderProvider.getIfAvailable();
        if (chatClientBuilder == null) {
            log.warn("[SPRING-AI] summarize skipped: ChatClient.Builder bean is not available");
            return Optional.empty();
        }

        String prompt = buildPrompt(event);

        try {
            String content = chatClientBuilder
                    .build()
                    .prompt()
                    .user(prompt)
                    .call()
                    .content();

            if (content == null || content.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(content.trim());
        } catch (Exception e) {
            log.warn("[SPRING-AI] summarize failed: {}", e.toString());
            return Optional.empty();
        }
    }

    private String buildPrompt(ErrorEvent event) {
        return """
                You are an SRE assistant. Summarize this backend error in Korean.
                Return exactly 3 short bullet lines:
                - root cause hypothesis
                - impact
                - immediate action

                service: %s
                time: %s
                correlationId: %s
                endpoint: %s %s
                exception: %s
                message: %s
                stackTraceTop:
                %s
                """.formatted(
                event.getService(),
                event.getOccurredAt(),
                event.getCorrelationId(),
                event.getMethod(),
                event.getPath(),
                event.getExceptionClass(),
                event.getMessage(),
                event.getStackTraceSnippet()
        );
    }
}

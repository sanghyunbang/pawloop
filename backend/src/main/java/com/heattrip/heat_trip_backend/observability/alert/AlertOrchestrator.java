package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.observability.ai.SpringAiErrorSummarizer;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.observability.error.ErrorEvent;
import com.heattrip.heat_trip_backend.observability.error.ErrorFingerprint;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class AlertOrchestrator {

    private final ObservabilityProperties props;
    private final AlertRateLimiter rateLimiter;
    private final SpringAiErrorSummarizer summarizer;
    private final SlackNotifier slackNotifier;

    public void notifyError(ErrorEvent event) {
        if (!props.isEnabled()) {
            return;
        }

        String fp = ErrorFingerprint.of(event);
        if (!rateLimiter.shouldSend(fp)) {
            log.info("[ALERT] suppressed by rate limiter: {}", fp);
            return;
        }

        String summary = summarizer.summarize(event).orElseGet(() -> defaultSummary(event));

        String text = """
                :rotating_light: *Backend Error Alert*
                - service: %s
                - correlationId: %s
                - endpoint: %s %s
                - exception: %s

                *GPT Summary*
                %s

                *Fingerprint*: `%s`
                """.formatted(
                event.getService(),
                nullSafe(event.getCorrelationId()),
                event.getMethod(),
                event.getPath(),
                event.getExceptionClass(),
                summary,
                fp.substring(0, 12)
        );

        boolean sent = slackNotifier.send(text);
        if (!sent) {
            log.warn("[ALERT] slack send skipped/failed for {} {}", event.getMethod(), event.getPath());
        }
    }

    private String defaultSummary(ErrorEvent event) {
        return "- ?? ??: " + nullSafe(event.getMessage()) + "\n"
                + "- ??: " + event.getMethod() + " " + event.getPath() + " ?? ?? ??\n"
                + "- ?? ??: correlationId(" + nullSafe(event.getCorrelationId()) + ")? ?? ?? ??";
    }

    private static String nullSafe(String s) {
        return s == null ? "N/A" : s;
    }
}

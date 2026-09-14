package com.heattrip.heat_trip_backend.walk.dto;

/**
 * AI 요약 👍/👎(#486 후속) — {@code PUT /api/walks/insights/{insightId}/feedback} 의 본문.
 *
 * @param value {@code up} · {@code down}, 지우려면 {@code null}. 다른 값은 400
 */
public record InsightFeedbackRequest(String value) {
}

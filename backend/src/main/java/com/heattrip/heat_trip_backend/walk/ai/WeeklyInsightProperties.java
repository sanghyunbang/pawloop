package com.heattrip.heat_trip_backend.walk.ai;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * AI 주간 요약의 손잡이 — 이슈 #486. {@code app.ai.weekly-insight.*}.
 *
 * @param enabled          끄면 키가 있어도 부르지 않는다
 * @param dailyCap         하루에 모델을 부르는 횟수 상한(서버 전체). 넘기면 조용히 1단계 문장만 — 로그 한 줄
 * @param maxRegenerations 한 사람 · 한 주에 입력이 바뀌어 다시 만드는 횟수 상한. 새 산책이 올 때마다
 *                         다시 만들되 이 수를 넘기면 마지막 문장을 그대로 둔다
 * @param timeoutSeconds   모델 응답을 기다리는 시간. 넘기면 이번엔 없이 나가고 다음 요청이 다시 시도한다
 */
@ConfigurationProperties(prefix = "app.ai.weekly-insight")
public record WeeklyInsightProperties(
        @DefaultValue("true") boolean enabled,
        @DefaultValue("200") int dailyCap,
        @DefaultValue("3") int maxRegenerations,
        @DefaultValue("12") int timeoutSeconds,
        @DefaultValue("true") boolean async) {
}

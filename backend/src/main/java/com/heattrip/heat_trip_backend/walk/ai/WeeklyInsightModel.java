package com.heattrip.heat_trip_backend.walk.ai;

import java.util.Optional;

/**
 * AI 주간 요약이 부르는 모델 — 이슈 #486.
 *
 * <p>서비스는 이 문 하나만 본다. 운영은 {@link SpringAiWeeklyInsightModel}(Spring AI · OpenAI)이고,
 * 테스트는 가짜를 꽂는다 — 키 없이도 "캐시 · 숫자 검사 · 상한" 을 잰다.
 */
public interface WeeklyInsightModel {

    /** 키와 모델이 준비됐는가. 아니면 기능은 조용히 꺼진 채 나간다 — {@code aiSummary: null}. */
    boolean available();

    /** 모델 이름 — 행에 남겨 "어느 모델의 문장인가" 를 안다. */
    String name();

    /** 문장을 받는다. 실패 · 시간 초과 · 빈 답이면 비어 있다(예외를 밖으로 내지 않는다). */
    Optional<String> complete(String system, String user);
}

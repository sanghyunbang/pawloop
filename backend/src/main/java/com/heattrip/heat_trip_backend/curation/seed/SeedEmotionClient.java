package com.heattrip.heat_trip_backend.curation.seed;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

/**
 * Python 추천 서비스의 {@code POST /seed-emotion} 호출 클라이언트.
 *
 * <p>요청 바디: {@code {"category": "<string>", "intro": "<string|null>"}}
 * <p>응답 바디: 6개 한글 감정 키 → float 가중치 맵 (합 ≈ 1.0).
 *
 * <p>{@code llmWebClient}(base-url: {@code llm.recommender.base-url})를 재사용한다.
 * 배치(1회성) 용도이므로 타임아웃/재시도는 적당히 보수적으로 둔다.
 */
@Slf4j
@Component
public class SeedEmotionClient {

    private final WebClient llmWebClient;

    public SeedEmotionClient(@Qualifier("llmWebClient") WebClient llmWebClient) {
        this.llmWebClient = llmWebClient;
    }

    private static final ParameterizedTypeRef EMOTION_MAP = new ParameterizedTypeRef();

    /** 응답 파싱용 타입 참조 (Map<String, Double>). */
    private static final class ParameterizedTypeRef
            extends org.springframework.core.ParameterizedTypeReference<Map<String, Double>> {
    }

    /**
     * /seed-emotion 호출.
     *
     * @param category 사람이 읽을 수 있는 카테고리 라벨 (cat3 대표명 또는 raw 코드)
     * @param intro    소개 텍스트 (없으면 null)
     * @return 감정→가중치 맵 (실패 시 예외 전파; 호출자가 per-place 단위로 처리)
     */
    public Map<String, Double> fetchSeedEmotion(String category, String intro) {
        Map<String, Object> body = new HashMap<>();
        body.put("category", category);
        body.put("intro", intro);

        return llmWebClient.post()
                .uri("/seed-emotion")
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .onStatus(s -> s.is4xxClientError() || s.is5xxServerError(), resp ->
                        resp.bodyToMono(String.class)
                                .defaultIfEmpty("")
                                .flatMap(b -> {
                                    log.error("[SEED] HTTP {} body={}", resp.statusCode(), b);
                                    return Mono.error(new RuntimeException(
                                            "seed-emotion HTTP " + resp.statusCode().value()));
                                }))
                .bodyToMono(EMOTION_MAP)
                .timeout(Duration.ofSeconds(30))
                .retryWhen(Retry.backoff(2, Duration.ofMillis(300))
                        .filter(ex -> !(ex instanceof WebClientResponseException)
                                || ((WebClientResponseException) ex).getStatusCode().is5xxServerError()))
                .block();
    }
}

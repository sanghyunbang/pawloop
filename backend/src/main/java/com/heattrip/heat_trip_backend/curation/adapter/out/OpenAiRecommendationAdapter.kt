package com.heattrip.heat_trip_backend.curation.adapter.out

import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendRequest
import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendResponse
import com.heattrip.heat_trip_backend.curation.port.RecommendationPort
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.http.MediaType
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.WebClientResponseException
import reactor.core.publisher.Mono
import reactor.util.retry.Retry
import java.time.Duration

@Component
class OpenAiRecommendationAdapter(
    @param: Qualifier("llmWebClient") private val llmWebClient: WebClient,
) : RecommendationPort {

    private val log = LoggerFactory.getLogger(OpenAiRecommendationAdapter::class.java)

    override fun getRecommendation(request: LlmRecommendRequest): LlmRecommendResponse? {
        log.info("[LLM] POST /recommend via OpenAiRecommendationAdapter")

        return llmWebClient.post()
            .uri("/recommend")
            .contentType(MediaType.APPLICATION_JSON)
            .accept(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .retrieve()
            .onStatus({ it.is4xxClientError || it.is5xxServerError }) { resp ->
                resp.bodyToMono(String::class.java)
                    .defaultIfEmpty("")
                    .flatMap { body ->
                        log.error("[LLM] HTTP {} body={}", resp.statusCode(), body)
                        Mono.error(RuntimeException("LLM HTTP ${resp.statusCode().value()}"))
                    }
            }
            .bodyToMono(LlmRecommendResponse::class.java)
            .timeout(Duration.ofSeconds(180))
            .retryWhen(
                Retry.backoff(2, Duration.ofMillis(300))
                    .filter { ex ->
                        ex !is WebClientResponseException || ex.statusCode.is5xxServerError
                    },
            )
            .doOnError { error ->
                log.error("[LLM] call failed: {}", error.toString())
            }
            .block()
    }
}

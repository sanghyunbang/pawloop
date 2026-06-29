// src/main/java/com/heattrip/heat_trip_backend/config/LlmWebClientConfig.java
package com.heattrip.heat_trip_backend.config;

import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import io.netty.handler.timeout.WriteTimeoutHandler;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.ExchangeFilterFunction;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Slf4j
@Configuration
public class LlmWebClientConfig {

    @Bean("llmWebClient")
    public WebClient llmWebClient(
            // ▶ 기존과 동일한 프로퍼티 사용, 기본값만 살짝 현실적으로 상향
            @Value("${llm.recommender.base-url}") String baseUrl,
            @Value("${llm.recommender.connect-timeout-ms:10000}") int connectTimeoutMs,   // (기존 5s → 10s) 네트워크 품질이 안 좋으면 5s 자주 터짐
            @Value("${llm.recommender.read-timeout-ms:120000}") int readTimeoutMs,       // (기존 30s → 120s) LLM 처리 특성상 30s는 짧음
            @Value("${llm.recommender.max-in-mem-bytes:33554432}") int maxInMemBytes     // (신규) 32MB: 큰 JSON 대비
    ) {
        // ⚠ 기존 문제 1: responseTimeout(응답 헤더 대기 상한) 없음 → 프록시/서버가 느릴 때 연결은 살아있어도 오래 대기
        // ⚠ 기존 문제 2: WriteTimeoutHandler 15s / ReadTimeoutHandler 30s → 실제 LLM 응답이 30~60s면 .timeout(75s) 도달 전에 먼저 끊김
        // ✔ 대응: responseTimeout을 readTimeoutMs와 맞추고, Read/WriteTimeout도 동일하게 넉넉히 설정
        HttpClient httpClient = HttpClient.create()
                .compress(true) // (신규) 서버가 gzip 지원 시 자동 압축 전송/수신 → 대용량 JSON에 유리
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, connectTimeoutMs)
                .responseTimeout(Duration.ofMillis(readTimeoutMs)) // (신규) 응답 헤더 대기 상한
                .doOnConnected(conn -> conn
                        .addHandlerLast(new ReadTimeoutHandler(readTimeoutMs, TimeUnit.MILLISECONDS))  // (기존 30s → 120s) 소켓 read idle 상한
                        .addHandlerLast(new WriteTimeoutHandler(readTimeoutMs, TimeUnit.MILLISECONDS)) // (기존 15s → 120s) 소켓 write idle 상한
                );

        // ⚠ 기존 문제 3: 대용량 응답 시 DataBufferLimitException 가능성 → maxInMemorySize 확장
        ExchangeStrategies strategies = ExchangeStrategies.builder()
                .codecs(c -> c.defaultCodecs().maxInMemorySize(maxInMemBytes))
                .build();

        return WebClient.builder()
                .baseUrl(baseUrl) // 예: http://127.0.0.1:8000
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .exchangeStrategies(strategies)
                .filter(logRequest())   // 간단 로깅
                .filter(logResponse())  // 간단 로깅
                .build();
    }

    private static ExchangeFilterFunction logRequest() {
        return ExchangeFilterFunction.ofRequestProcessor(req -> {
            log.info("[LLM] -> {} {}", req.method(), req.url());
            return Mono.just(req);
        });
    }

    private static ExchangeFilterFunction logResponse() {
        return ExchangeFilterFunction.ofResponseProcessor(resp -> {
            log.info("[LLM] <- {}", resp.statusCode());
            return Mono.just(resp);
        });
    }
}

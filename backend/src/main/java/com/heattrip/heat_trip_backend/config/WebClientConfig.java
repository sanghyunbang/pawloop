package com.heattrip.heat_trip_backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.http.HttpHeaders;


@Configuration
public class WebClientConfig {
    
    @Bean
    public WebClient tourApiWebClient(WebClient.Builder builder) {
        // ExchangeStrategies를 사용하여 버퍼 크기 제한을 늘립니다.
        ExchangeStrategies exchangeStrategies = ExchangeStrategies.builder()
                .codecs(clientCodecConfigurer -> clientCodecConfigurer
                    .defaultCodecs()
                    .maxInMemorySize(10 * 1024 * 1024) // 예시: 10MB로 설정 (10 * 1024 * 1024 bytes)
                )
                .build();
        return builder
                .baseUrl("https://apis.data.go.kr/B551011/KorService2")
                .exchangeStrategies(exchangeStrategies)
                .build();
    }

    // Kakao Local API 전용 WebClient
    @Bean("kakaoWebClient")
    public WebClient kakaoWebClient(
            WebClient.Builder builder,
            @Value("${kakao.api.base-url}") String baseUrl,
            @Value("${kakao.api.rest-key}") String restKey
    ) {
        return builder
                .baseUrl(baseUrl) // https://dapi.kakao.com
                .defaultHeader(HttpHeaders.AUTHORIZATION, "KakaoAK " + restKey)
                .build();
    }
}

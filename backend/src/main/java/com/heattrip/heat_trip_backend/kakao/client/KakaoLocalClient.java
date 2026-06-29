package com.heattrip.heat_trip_backend.kakao.client;

import com.heattrip.heat_trip_backend.kakao.dto.KakaoKeywordResponse;
import org.springframework.beans.factory.annotation.Qualifier;      // [1]
import org.springframework.beans.factory.annotation.Value;          // [2]
import org.springframework.stereotype.Component;                    // [3]
import org.springframework.web.reactive.function.client.WebClient;  // [4]
import reactor.core.publisher.Mono;                                 // [5]

/**
 * Kakao Local(키워드 검색) API 호출 전용 클라이언트.
 * A small wrapper around WebClient to call Kakao's keyword search endpoint.
 */
@Component  // 스프링 빈으로 등록 → 다른 클래스에서 의존성 주입 가능 [3]
public class KakaoLocalClient {

    // Kakao API에 Authorization 헤더가 미리 세팅된 WebClient [4]
    private final WebClient kakaoWebClient;

    // Kakao API 정렬 기준 (distance | accuracy). application.properties로 주입 [2]
    private final String sort;

    // 검색 반경(m). application.properties로 주입 [2]
    private final int radius;

    /**
     * 생성자 주입(Constructor Injection).
     * - @Qualifier("kakaoWebClient"): config/WebClientConfig에서 만든 특정 WebClient 빈을 지정. [1]
     * - @Value: application.properties 값을 주입받아 런타임 설정 가능. [2]
     */
    public KakaoLocalClient(
            @Qualifier("kakaoWebClient") WebClient kakaoWebClient,
            @Value("${backfill.kakao.sort:distance}") String sort,
            @Value("${backfill.kakao.radius:20000}") int radius
    ) {
        this.kakaoWebClient = kakaoWebClient;
        this.sort = sort;
        this.radius = radius;
    }

    /**
     * Kakao 키워드 검색 호출.
     * @param query 검색 키워드(예: 장소명) — 서버가 URL 인코딩을 자동 처리. [6]
     * @param x     중심 경도(longitude) — Kakao는 'x'를 경도로 사용. [7]
     * @param y     중심 위도(latitude)  — Kakao는 'y'를 위도로 사용.  [7]
     * @return {@code Mono<KakaoKeywordResponse>} (비동기 단일값) — 호출부에서 .block() 또는 reactive 체인으로 사용. [5][8]
     */
    public Mono<KakaoKeywordResponse> searchKeyword(String query, double x, double y) {
        return kakaoWebClient
                .get() // HTTP GET 메서드 선택
                .uri(uri -> uri
                        .path("/v2/local/search/keyword.json") // 엔드포인트 경로
                        // --- 쿼리 파라미터 구성 ---
                        .queryParam("query", query)            // 검색어(필수)
                        .queryParam("x", x)                    // 중심 경도 (lon)
                        .queryParam("y", y)                    // 중심 위도 (lat)
                        .queryParam("radius", radius)          // 반경(m) 0~20000 [API 제한]
                        .queryParam("size", 15)                // 페이지 크기(1~15) [카카오 제한]
                        .queryParam("sort", sort)              // accuracy | distance
                        .build())
                // --- 요청 전송 및 응답 바디 매핑 ---
                .retrieve()                                    // 상태코드 4xx/5xx면 WebClientResponseException 발생 [9]
                .bodyToMono(KakaoKeywordResponse.class);       // JSON → DTO 역직렬화 [10]
    }
}

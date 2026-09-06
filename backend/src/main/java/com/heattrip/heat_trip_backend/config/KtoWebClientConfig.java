package com.heattrip.heat_trip_backend.config;

import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import io.netty.handler.timeout.WriteTimeoutHandler;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.util.DefaultUriBuilderFactory;

import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

/**
 * 관광공사(KTO) 프록시가 쓰는 WebClient 둘 — 이슈 #40. #291 이 공공데이터 레이어용 셋을 더했다.
 *
 * <h2>왜 기존 {@code tourApiWebClient} 를 안 쓰는가</h2>
 * <p>두 가지 이유가 있다.
 *
 * <ol>
 *   <li><b>base URL 이 다르다.</b> 앱이 쓰던 두 API 는 서로 다른 서비스다 —
 *       주변 장소는 {@code KorPetTourService2}, 개요는 {@code KorService2} 다.
 *       기존 빈은 후자에 고정돼 있다.</li>
 *   <li><b>타임아웃이 하나도 없다.</b> {@code WebClientConfig.tourApiWebClient} 는 버퍼
 *       크기만 키워 뒀고 연결·응답·소켓 타임아웃이 전부 없다. 그 상태로 <b>인증 없는 공개
 *       경로</b> 뒤에 두면, KTO 가 느려지는 순간 톰캣 스레드가 무한정 묶인다.</li>
 * </ol>
 *
 * <p>기존 빈은 <b>건드리지 않는다.</b> 감정추천 적재({@code PlaceImportService})가 쓰고
 * 있고, 그쪽은 배치라 이 이슈의 위험 모델이 다르다.
 *
 * <h2>타임아웃을 네 겹으로 거는 이유</h2>
 * <p>{@code LlmWebClientConfig} 가 같은 이유로 이미 넷을 건다.
 * <ul>
 *   <li>{@code CONNECT_TIMEOUT_MILLIS} — TCP 연결이 안 될 때</li>
 *   <li>{@code responseTimeout} — 연결은 됐는데 응답 헤더가 안 올 때</li>
 *   <li>{@code ReadTimeoutHandler} — 헤더는 왔는데 본문이 끊길 때</li>
 *   <li>{@code WriteTimeoutHandler} — 보내는 쪽이 막힐 때</li>
 * </ul>
 * <p>하나만 걸면 나머지 셋의 경로로 무한 대기가 남는다. 부르는 쪽은 여기에 더해
 * {@code Mono.timeout()} 을 한 겹 더 건다 — 위 넷은 소켓 수준이고 그것은 <b>호출 전체</b>의
 * 상한이라 성질이 다르다.
 *
 * <h2>{@code serviceKey} 를 여기 두지 않는다</h2>
 * <p>{@code defaultUriVariables} 나 기본 쿼리로 박으면 <b>모든 요청 URL 에 키가 들어가고</b>
 * 그 URL 이 로그·예외 메시지·메트릭 태그로 샌다. 키는 호출부가 URI 를 조립할 때만 붙이고,
 * 호출부는 URL 을 로그에 찍지 않는다.
 */
@Configuration
public class KtoWebClientConfig {

    /** KTO 응답은 numOfRows 가 크면 수백 KB 다. 기존 빈과 같은 10MB. */
    private static final int MAX_IN_MEMORY_BYTES = 10 * 1024 * 1024;

    /** 반려동반 장소 목록 · 반려동반 상세. */
    public static final String KOR_PET_TOUR = "korPetTourWebClient";

    /** 일반 관광 상세(개요). */
    public static final String KOR_SERVICE_DETAIL = "korServiceDetailWebClient";

    /** 행정안전부 인허가(동물병원·동물판매업) — 이슈 #291. 같은 포털, 같은 키, 다른 게이트웨이 경로. */
    public static final String LOCALDATA = "localDataWebClient";

    /** 두루누비 걷기여행길 코스 목록 — 이슈 #291. */
    public static final String DURUNUBI = "durunubiWebClient";

    /**
     * 두루누비 GPX 파일 — 이슈 #291. 기본 URL 이 없다(코스 목록이 주는 주소를 그대로 연다).
     * 파일이 1MB 안팎이라 읽기 타임아웃이 API 보다 길다.
     */
    public static final String GPX = "gpxWebClient";

    @Bean(KOR_PET_TOUR)
    public WebClient korPetTourWebClient(
            WebClient.Builder builder,
            @Value("${app.kto.connect-timeout-ms:3000}") int connectTimeoutMs,
            @Value("${app.kto.read-timeout-ms:5000}") int readTimeoutMs) {
        return build(builder, "https://apis.data.go.kr/B551011/KorPetTourService2",
                connectTimeoutMs, readTimeoutMs);
    }

    @Bean(KOR_SERVICE_DETAIL)
    public WebClient korServiceDetailWebClient(
            WebClient.Builder builder,
            @Value("${app.kto.connect-timeout-ms:3000}") int connectTimeoutMs,
            @Value("${app.kto.read-timeout-ms:5000}") int readTimeoutMs) {
        return build(builder, "https://apis.data.go.kr/B551011/KorService2",
                connectTimeoutMs, readTimeoutMs);
    }

    @Bean(LOCALDATA)
    public WebClient localDataWebClient(
            WebClient.Builder builder,
            @Value("${app.place.layer.localdata-base-url:https://apis.data.go.kr/1741000}") String baseUrl,
            @Value("${app.kto.connect-timeout-ms:3000}") int connectTimeoutMs,
            @Value("${app.place.layer.api-read-timeout-ms:10000}") int readTimeoutMs) {
        return build(builder, baseUrl, connectTimeoutMs, readTimeoutMs);
    }

    @Bean(DURUNUBI)
    public WebClient durunubiWebClient(
            WebClient.Builder builder,
            @Value("${app.place.layer.durunubi-base-url:https://apis.data.go.kr/B551011/Durunubi}") String baseUrl,
            @Value("${app.kto.connect-timeout-ms:3000}") int connectTimeoutMs,
            @Value("${app.place.layer.api-read-timeout-ms:10000}") int readTimeoutMs) {
        return build(builder, baseUrl, connectTimeoutMs, readTimeoutMs);
    }

    @Bean(GPX)
    public WebClient gpxWebClient(
            WebClient.Builder builder,
            @Value("${app.kto.connect-timeout-ms:3000}") int connectTimeoutMs,
            @Value("${app.place.layer.gpx-read-timeout-ms:15000}") int readTimeoutMs) {
        return builder
                .clientConnector(new ReactorClientHttpConnector(httpClient(connectTimeoutMs, readTimeoutMs)))
                .exchangeStrategies(strategies())
                .build();
    }

    private static HttpClient httpClient(int connectTimeoutMs, int readTimeoutMs) {
        return HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, connectTimeoutMs)
                .responseTimeout(Duration.ofMillis(readTimeoutMs))
                .doOnConnected(conn -> conn
                        .addHandlerLast(new ReadTimeoutHandler(readTimeoutMs, TimeUnit.MILLISECONDS))
                        .addHandlerLast(new WriteTimeoutHandler(readTimeoutMs, TimeUnit.MILLISECONDS)));
    }

    private static ExchangeStrategies strategies() {
        return ExchangeStrategies.builder()
                .codecs(c -> c.defaultCodecs().maxInMemorySize(MAX_IN_MEMORY_BYTES))
                .build();
    }

    private static WebClient build(WebClient.Builder builder, String baseUrl,
                                   int connectTimeoutMs, int readTimeoutMs) {
        // 인코딩을 **끈다**. TOUR.API.SECRET 은 이미 URL 인코딩된 문자열이라
        // 기본 모드(TEMPLATE_AND_VALUES)로 두면 % 가 %25 로 다시 인코딩돼
        // KTO 가 인증 실패를 돌려주고, 그 실패는 HTTP 200 이라 "장소 없음" 으로 보인다.
        DefaultUriBuilderFactory uriFactory = new DefaultUriBuilderFactory(baseUrl);
        uriFactory.setEncodingMode(DefaultUriBuilderFactory.EncodingMode.NONE);

        return builder
                .uriBuilderFactory(uriFactory)
                .clientConnector(new ReactorClientHttpConnector(httpClient(connectTimeoutMs, readTimeoutMs)))
                .exchangeStrategies(strategies())
                .build();
    }
}

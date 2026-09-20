package com.heattrip.heat_trip_backend.place;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * OpenRouteService(ORS) — 코스 추천의 왕복 산책 경로를 만드는 바깥 API. 이슈 #725.
 *
 * <p>키는 <b>서버에만</b> 있고({@code ORS_API_KEY}, 앱에는 절대 안 내려간다), 요청 <b>헤더</b>로
 * 나간다 — KTO 처럼 URL 에 싣지 않으므로 {@code ExchangeFunctions} 의 URL 로그에 남을 일이
 * 없다(#192 의 그 자리). 키가 비어 있으면 기능이 조용히 꺼진다 — 앱은 "지금은 추천을 못 받아요"
 * 를 본다. 슬랙 웹훅(#707)·Apple 키(#301)와 같은 태도다.
 */
@Component
@ConfigurationProperties(prefix = "app.ors")
@Getter
@Setter
public class OrsProperties {

    /** {@code ORS_API_KEY}. 비어 있으면 기능이 꺼진다. 어디에도 찍지 않는다. */
    private String apiKey = "";

    private String baseUrl = "https://api.openrouteservice.org";

    /**
     * 한 코스를 만들 때 seed 를 몇 개 돌려 보나. ORS 의 왕복은 seed 마다 모양이 달라 2km 를
     * 부탁해도 5.5km 가 오는 일이 있다(실측 2026-09-20). 셋 중 목표에 가장 가까운 것을 고른다.
     * 한도가 빠듯하면 줄인다 — 한 번 고른 코스는 저장돼 다시 안 묻는다.
     */
    private int loopAttempts = 3;

    /** 왕복을 만들 때 찍는 경유점 수. 3 이 길이를 가장 잘 지켰다(5 는 크게 넘쳤다). */
    private int loopPoints = 3;

    private int connectTimeoutMs = 3000;

    private int readTimeoutMs = 8000;

    public boolean hasKey() {
        return apiKey != null && !apiKey.isBlank();
    }
}

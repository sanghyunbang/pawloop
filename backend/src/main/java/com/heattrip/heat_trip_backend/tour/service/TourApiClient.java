package com.heattrip.heat_trip_backend.tour.service;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

@Service
public class TourApiClient {

    private final WebClient tourApiWebClient;
    private final String secret;

    //  이 생성자에서 어떤 WebClient 빈을 쓸지 명시합니다.
    public TourApiClient(
            @Qualifier("tourApiWebClient") WebClient tourApiWebClient,
            @Value("${TOUR.API.SECRET}") String secret
    ) {
        this.tourApiWebClient = tourApiWebClient;
        this.secret = secret;
    }

    public String fetchAreaBasedList(int areaCode, int pageNo, int numOfRows) {
        return tourApiWebClient.get()
            .uri(uri -> uri.path("/areaBasedList2")
                .queryParam("serviceKey", secret)
                .queryParam("MobileOS", "WEB")
                .queryParam("MobileApp", "HeatTrip")
                .queryParam("arrange", "C")
                .queryParam("areaCode", areaCode)
                .queryParam("pageNo", pageNo)
                .queryParam("numOfRows", numOfRows)
                .queryParam("_type", "json")
                .build())
            .retrieve()
            .bodyToMono(String.class)
            .block();
    }
}

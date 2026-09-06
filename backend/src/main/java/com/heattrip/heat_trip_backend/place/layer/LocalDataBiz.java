package com.heattrip.heat_trip_backend.place.layer;

import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

/**
 * 인허가 데이터에서 받는 업종 둘 — 이슈 #291.
 *
 * <p>둘 다 행정안전부의 <b>전국</b> 데이터다(공공데이터포털 "행정안전부_동물_동물병원
 * 조회서비스"·"행정안전부_동물_동물판매업 조회서비스"). #291 본문은 서울 열린데이터광장만 보고
 * "서울만 있다" 고 적었는데, 그 자료의 원천인 지방행정인허가데이터가 전국을 한 API 로 준다
 * (동물병원 9,445건 · 동물판매업 8,907건, 2025-11 기준 폐업 포함).
 *
 * <p>같은 게이트웨이({@code apis.data.go.kr/1741000})라 경로 조각만 다르고 응답 모양은 같다.
 */
public enum LocalDataBiz {

    /** 동물병원 — {@code /animal_hospitals/info}. */
    VET("animal_hospitals", PlaceDto.SOURCE_VET),

    /** 동물판매업 — {@code /animal_sales/info}. 펫샵 칩이다. */
    SHOP("animal_sales", PlaceDto.SOURCE_SHOP);

    private final String pathSegment;
    private final String category;

    LocalDataBiz(String pathSegment, String category) {
        this.pathSegment = pathSegment;
        this.category = category;
    }

    /** 게이트웨이 경로. {@code /info} 가 현재 목록, {@code /history} 가 이력이다 — 우리는 현재만 본다. */
    public String path() {
        return "/" + pathSegment + "/info";
    }

    /** 계약의 {@code PlaceCategory} 값이자 {@code Place.source} 값. */
    public String category() {
        return category;
    }
}

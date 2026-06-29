package com.heattrip.heat_trip_backend.kakao.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;           // [1]
import com.fasterxml.jackson.annotation.JsonProperty;                 // [2]
import java.util.List;

/**
 * Kakao Local "keyword search" 응답 DTO.
 * 매핑의 안정성을 위해: 1) 미지 필드는 무시, 2) snake_case → camelCase를 @JsonProperty로 명시.  [1][2]
 */
@JsonIgnoreProperties(ignoreUnknown = true)  // 응답에 추가 필드가 생겨도 역직렬화 오류 방지 [1]
public class KakaoKeywordResponse {

    // 응답 메타데이터(총 건수, 페이지 등)
    private Meta meta;

    // 실제 검색 결과 목록
    private List<Document> documents;

    // ─────────────────────────────────────────────────────
    // 접근자 (Jackson은 필드/게터 어느 쪽이든 바인딩 가능하나, 게터를 두면 사용처에서 편리)
    public Meta getMeta() { return meta; }
    public List<Document> getDocuments() { return documents; }

    // ─────────────────────────────────────────────────────
    // 내부 클래스: 메타 영역
    @JsonIgnoreProperties(ignoreUnknown = true)  // 방어적 매핑 [1]
    public static class Meta {
        @JsonProperty("total_count")    public int totalCount;     // 질의 전체 일치 건수
        @JsonProperty("pageable_count") public int pageableCount;  // 노출 가능/페이징 가능한 최대 건수(≤45)
        @JsonProperty("is_end")         public boolean isEnd;      // 현재 페이지가 마지막인지
        // same_name 등 부가 메타가 올 수 있으나, 이번 작업에 불필요해 생략(무시 처리) [1]
    }

    // ─────────────────────────────────────────────────────
    // 내부 클래스: 결과 문서(장소 1건)
    @JsonIgnoreProperties(ignoreUnknown = true)  // 방어적 매핑 [1]
    public static class Document {
        @JsonProperty("id")                   public String id;                 // Kakao place id (문자형) [3]
        @JsonProperty("place_name")           public String placeName;          // 장소명
        @JsonProperty("category_name")        public String categoryName;       // 전체 카테고리 경로 문자열
        @JsonProperty("category_group_code")  public String categoryGroupCode;  // 상위 카테고리 코드(AT4/CT1/…)
        @JsonProperty("category_group_name")  public String categoryGroupName;  // 상위 카테고리명
        @JsonProperty("place_url")            public String placeUrl;           // 상세 페이지 URL

        // 좌표는 Kakao가 문자열로 제공 → Double로 바로 받으면 파싱 실패 시 전체 역직렬화가 깨질 수 있어 문자열로 수신 후, 사용 시 파싱 권장 [4]
        @JsonProperty("x")                    public String x;  // longitude (경도)
        @JsonProperty("y")                    public String y;  // latitude  (위도)

        // x,y를 전달한 경우에만 등장. 미터 단위 문자열(예: "418") → 사용 시 Integer/Double 변환 [5]
        @JsonProperty("distance")             public String distance;

        @JsonProperty("address_name")         public String addressName;        // 지번 주소
        @JsonProperty("road_address_name")    public String roadAddressName;    // 도로명 주소
        // phone 등 추가 필드는 필요 시 확장 가능. 현재는 무시(안전) [1]
    }
}

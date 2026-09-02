package com.heattrip.heat_trip_backend.place.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * KTO 항목 하나를 {@link PlaceDto} 로 옮길 때 <b>무엇을 버리는가</b> — 이슈 #24(ADR-0017 규약 1).
 *
 * <h2>왜 여기서만 볼 수 있는가</h2>
 * <p>{@code PlaceProxyIntegrationTest} 의 가짜 KTO 는 {@code fetchNearby} 를 통째로 갈아 끼워
 * 이미 만들어진 {@code PlaceDto} 를 돌려준다. 그래서 <b>이 매핑을 한 줄도 지나지 않는다.</b>
 * 상류 JSON 의 어떤 모양이 목록에 실리면 안 되는지는 여기서만 잠긴다.
 *
 * <p>네트워크를 타지 않는다.
 */
class KtoPlaceMappingTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    @DisplayName("정상 항목은 그대로 옮긴다")
    void mapsAWellFormedItem() {
        PlaceDto place = KtoApiClient.toPlace(item("""
                {"contentid":"2733967","title":"서울숲","mapy":"37.5445","mapx":"127.0374",
                 "addr1":"서울 성동구","contenttypeid":"12","tel":"02-000-0000"}
                """));

        assertThat(place).isNotNull();
        assertThat(place.contentId()).isEqualTo("2733967");
        assertThat(place.source()).isEqualTo(PlaceDto.SOURCE_KTO);
    }

    @Test
    @DisplayName("contentId 가 없으면 버린다 — 목록에 떠도 누를 수 없는 줄이다")
    void dropsAnItemWithoutAContentId() {
        // 상세로 들어가는 유일한 열쇠가 이 값이다(`/api/places/{contentId}`). 없으면 앱은
        // 마커를 찍을 수는 있어도 그 마커를 눌렀을 때 부를 경로가 없다.
        //
        // 게다가 PlaceDto 는 @JsonInclude(NON_NULL) 이라 이런 항목은 contentId 키가
        // **통째로 빠진 채** 나간다 — 계약이 그 필드를 required 로 선언한 순간 그대로 위반이다.
        assertThat(KtoApiClient.toPlace(item("""
                {"title":"이름은 있다","mapy":"37.5445","mapx":"127.0374","addr1":"서울"}
                """)))
                .isNull();
    }

    @Test
    @DisplayName("contentId 가 공백뿐이어도 버린다")
    void dropsAnItemWhoseContentIdIsBlank() {
        assertThat(KtoApiClient.toPlace(item("""
                {"contentid":"   ","title":"서울숲","mapy":"37.5445","mapx":"127.0374"}
                """)))
                .isNull();
    }

    @Test
    @DisplayName("좌표가 없으면 버린다 — 앱이 0,0 에 마커를 그린다")
    void dropsAnItemWithoutCoordinates() {
        assertThat(KtoApiClient.toPlace(item("""
                {"contentid":"111","title":"좌표 없음","addr1":"서울"}
                """)))
                .isNull();
    }

    @Test
    @DisplayName("title·addr 이 없으면 빈 문자열로 채운다 — 이건 버리지 않는다")
    void keepsAnItemWithoutTitleOrAddress() {
        // 이름과 주소는 없어도 지도에 찍히고 상세로 들어갈 수 있다. contentId·좌표와 달리
        // "그 줄로 아무것도 못 한다" 가 아니므로 버리는 대신 빈 문자열로 눕힌다.
        PlaceDto place = KtoApiClient.toPlace(item("""
                {"contentid":"111","mapy":"37.5445","mapx":"127.0374"}
                """));

        assertThat(place).isNotNull();
        assertThat(place.title()).isEmpty();
        assertThat(place.addr()).isEmpty();
    }

    private static JsonNode item(String json) {
        try {
            return MAPPER.readTree(json);
        } catch (Exception e) {
            throw new IllegalStateException("테스트 픽스처가 JSON 이 아니다: " + json, e);
        }
    }
}

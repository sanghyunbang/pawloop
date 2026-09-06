package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 인허가 항목 → 계약의 {@code Place} — 이슈 #291. 필드 이름은 공공데이터포털 명세의 것이다.
 */
class LocalDataPlaceMapperTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private final Tm5174 tm = new Tm5174();

    /** 서울 열린데이터광장 sample 행(2026-09-06)을 포털 명세의 필드 이름으로 옮긴 것. */
    private static final String VET = """
            {"MNG_NO":"322000001020260003","BPLC_NM":"늘서울피부과동물병원","SALS_STTS_CD":"01",
             "SALS_STTS_NM":"영업/정상","CRD_INFO_X":"202875.328642756    ","CRD_INFO_Y":"445077.204272347    ",
             "ROAD_NM_ADDR":"서울특별시 강남구 논현로 607, 신양빌딩 3층 (논현동)",
             "LOTNO_ADDR":"서울특별시 강남구 논현동 192-6 신양빌딩","TELNO":"02-518-3650"}
            """;

    @Test
    @DisplayName("정상 항목은 vet:관리번호 · 도로명주소 · WGS84 좌표로 옮긴다")
    void mapsAWellFormedItem() {
        PlaceDto place = LocalDataPlaceMapper.toPlace(item(VET), LocalDataBiz.VET, tm).orElseThrow();

        assertThat(place.contentId()).isEqualTo("vet:322000001020260003");
        assertThat(place.title()).isEqualTo("늘서울피부과동물병원");
        assertThat(place.source()).isEqualTo("vet");
        assertThat(place.category()).isEqualTo("vet");
        assertThat(place.categoryKey()).isEqualTo("vet");
        assertThat(place.contentTypeId()).as("KTO 체계의 값이라 채울 것이 없다").isNull();
        assertThat(place.addr()).startsWith("서울특별시 강남구 논현로 607");
        assertThat(place.tel()).isEqualTo("02-518-3650");
        assertThat(place.lat()).isCloseTo(37.5079, org.assertj.core.data.Offset.offset(0.001));
        assertThat(place.lng()).isCloseTo(127.0333, org.assertj.core.data.Offset.offset(0.001));
        assertThat(place.distM()).isNull();
    }

    @Test
    @DisplayName("좌표가 빈 신규 인허가는 버린다 — 지도에 못 찍는다 (서울 실측: 개업 며칠 안 된 곳)")
    void dropsAnItemWithoutCoordinates() {
        String blank = VET.replace("\"CRD_INFO_X\":\"202875.328642756    \"", "\"CRD_INFO_X\":\"                    \"");
        assertThat(LocalDataPlaceMapper.toPlace(item(blank), LocalDataBiz.VET, tm)).isEmpty();
    }

    @Test
    @DisplayName("영업 중이 아니면 버린다 — 호출이 걸러도 한 번 더 본다")
    void dropsAClosedBusiness() {
        String closed = VET.replace("\"SALS_STTS_CD\":\"01\"", "\"SALS_STTS_CD\":\"03\"");
        assertThat(LocalDataPlaceMapper.toPlace(item(closed), LocalDataBiz.VET, tm)).isEmpty();
    }

    @Test
    @DisplayName("관리번호나 이름이 없으면 버린다 — 다시 알아볼 열쇠가 없다")
    void dropsAnItemWithoutKeyOrName() {
        assertThat(LocalDataPlaceMapper.toPlace(item(VET.replace("\"MNG_NO\":\"322000001020260003\",", "")),
                LocalDataBiz.VET, tm)).isEmpty();
        assertThat(LocalDataPlaceMapper.toPlace(item(VET.replace("늘서울피부과동물병원", "  ")),
                LocalDataBiz.VET, tm)).isEmpty();
    }

    @Test
    @DisplayName("도로명주소가 없으면 지번주소를 쓴다")
    void fallsBackToLotAddress() {
        String noRoad = VET.replace("\"ROAD_NM_ADDR\":\"서울특별시 강남구 논현로 607, 신양빌딩 3층 (논현동)\",", "");
        PlaceDto place = LocalDataPlaceMapper.toPlace(item(noRoad), LocalDataBiz.VET, tm).orElseThrow();
        assertThat(place.addr()).isEqualTo("서울특별시 강남구 논현동 192-6 신양빌딩");
    }

    @Test
    @DisplayName("판매업은 shop 이고 상세 업무 구분이 summary 로 온다")
    void mapsAShopWithItsTaskName() {
        String shop = VET.replace("\"TELNO\":\"02-518-3650\"", "\"TELNO\":\"\",\"DTL_TASK_SE_NM\":\"동물판매업\"");
        PlaceDto place = LocalDataPlaceMapper.toPlace(item(shop), LocalDataBiz.SHOP, tm).orElseThrow();

        assertThat(place.contentId()).startsWith("shop:");
        assertThat(place.source()).isEqualTo("shop");
        assertThat(place.summary()).isEqualTo("동물판매업");
        assertThat(place.tel()).as("빈 문자열은 null 로 눕힌다").isNull();
    }

    private static JsonNode item(String json) {
        try {
            return MAPPER.readTree(json);
        } catch (Exception e) {
            throw new IllegalArgumentException(e);
        }
    }

    @SuppressWarnings("unused")
    private static Optional<PlaceDto> none() {
        return Optional.empty();
    }
}

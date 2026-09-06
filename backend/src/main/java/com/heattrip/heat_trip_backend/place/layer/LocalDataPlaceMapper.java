package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.JsonNode;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;

import java.util.Optional;

/**
 * 인허가 항목 하나를 계약의 {@code Place} 로 — 이슈 #291.
 *
 * <p>필드 이름은 공공데이터포털 명세(행정안전부_동물_동물병원 조회서비스)의 것이다.
 * 서울 열린데이터광장의 같은 데이터는 {@code BPLCNM}·{@code SITEWHLADDR} 처럼 이름이 다르다 —
 * 그쪽을 붙이려면 여기가 아니라 새 매퍼다.
 *
 * <h2>{@code contentId} 는 {@code 출처:관리번호} 다</h2>
 * <p>KTO 의 {@code contentid} 와 같은 자리에 인허가 관리번호를 그대로 넣으면 두 체계의 숫자가
 * 겹칠 수 있다. 접두사가 붙은 값은 KTO 상세({@code GET /api/places/{contentId}})에서 404 다 —
 * 앱은 이 출처의 상세를 부르지 않는다(카탈로그 항목이 곧 전부다). ADR-0017 이 미뤄 둔
 * "KTO 가 아닌 출처의 키 모양" 을 여기서 정한다: {@code vet:311000001020260003}.
 */
public final class LocalDataPlaceMapper {

    private LocalDataPlaceMapper() {
    }

    /**
     * @return 지도에 찍을 수 있는 항목이면 값, 좌표·이름·관리번호가 없거나 영업 중이 아니면 비어 있다
     */
    public static Optional<PlaceDto> toPlace(JsonNode item, LocalDataBiz biz, Tm5174 tm) {
        String mgtNo = text(item, "MNG_NO");
        String name = text(item, "BPLC_NM");
        if (mgtNo == null || name == null) {
            return Optional.empty();
        }

        // 호출이 영업 중만 받지만, 서버가 필터를 무시했을 때를 위해 한 번 더 본다.
        String status = text(item, "SALS_STTS_CD");
        if (status != null && !LocalDataApiClient.OPEN_STATUS_CODE.equals(status)) {
            return Optional.empty();
        }

        Double x = number(item, "CRD_INFO_X");
        Double y = number(item, "CRD_INFO_Y");
        if (x == null || y == null) {
            // 좌표가 빈 신규 인허가가 있다(서울 실측: 개업 며칠 안 된 곳). 지도에 못 찍는다.
            return Optional.empty();
        }
        Optional<double[]> latLng = tm.toLatLng(x, y);
        if (latLng.isEmpty()) {
            return Optional.empty();
        }

        String addr = text(item, "ROAD_NM_ADDR");
        if (addr == null) {
            addr = text(item, "LOTNO_ADDR");
        }

        // 판매업은 상세 업무 구분(동물판매업/동물미용업 …)이 온다. 병원은 그 필드가 없다.
        String summary = text(item, "DTL_TASK_SE_NM");

        return Optional.of(new PlaceDto(
                biz.category() + ":" + mgtNo,
                name,
                biz.category(),
                biz.category(),
                null,
                latLng.get()[0],
                latLng.get()[1],
                addr == null ? "" : addr,
                text(item, "TELNO"),
                null,
                null,
                summary));
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) {
            return null;
        }
        String text = value.asText().strip();
        return text.isEmpty() ? null : text;
    }

    private static Double number(JsonNode node, String field) {
        String raw = text(node, field);
        if (raw == null) {
            return null;
        }
        try {
            return Double.parseDouble(raw);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}

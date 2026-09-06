package com.heattrip.heat_trip_backend.place;

import java.util.Optional;

/**
 * {@code place_catalog} 의 행 하나가 담는 <b>출처</b> — 이슈 #291.
 *
 * <p>#273 에서 이 표는 행이 하나였다(KTO 전국 한 벌). 동물병원·펫샵(행정안전부 인허가)과
 * 산책로(두루누비)가 붙으면서 <b>출처마다 한 벌</b>이 됐다. 셋은 갱신 주기도 예산도 다르다 —
 * KTO 는 매일 새벽에 데우고, 인허가는 월 1회, 두루누비는 월 1회다. 한 벌에 섞어 두면
 * KTO 가 아픈 날 병원까지 사라지고, 인허가를 다시 받는 날 KTO 열 페이지를 또 태운다.
 *
 * <p>앱이 받는 응답은 여전히 <b>하나</b>다 — {@code GET /api/places/catalog} 가 세 벌을
 * 이어 붙인다. 앱은 출처가 몇인지 모른다.
 *
 * <h2>{@link #id()} 가 고정인 이유</h2>
 * <p>행이 출처당 정확히 하나여야 한다. 자동 증가 키를 쓰면 "이 출처의 행" 을 찾을 때 항상
 * {@code source} 로 조회해야 하고, 같은 출처의 행이 둘이 되는 것을 막는 것은 UNIQUE 뿐이다.
 * 번호를 고정하면 조회가 PK 이고, 마이그레이션(24)이 옛 행 1 을 {@code kto} 로 그대로 둘 수 있다.
 */
public enum CatalogSource {

    /** 관광공사 반려동반 장소 — 매일 새벽 예열(#279). */
    KTO(1, "kto"),

    /** 행정안전부 인허가 — 동물병원({@code vet}) · 동물판매업({@code shop}). 월 1회. */
    LOCALDATA(2, "localdata"),

    /** 관광공사 두루누비 걷기여행길 — 산책로({@code trail}). 월 1회. */
    DURUNUBI(3, "durunubi");

    private final int id;
    private final String wireValue;

    CatalogSource(int id, String wireValue) {
        this.id = id;
        this.wireValue = wireValue;
    }

    /** {@code place_catalog.id}. */
    public int id() {
        return id;
    }

    /** {@code place_catalog.source} 에 저장하는 문자열. 소문자다. */
    public String wireValue() {
        return wireValue;
    }

    public static Optional<CatalogSource> ofId(int id) {
        for (CatalogSource source : values()) {
            if (source.id == id) {
                return Optional.of(source);
            }
        }
        return Optional.empty();
    }
}

package com.heattrip.heat_trip_backend.place.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * 계약({@code openapi.yaml})의 {@code Place} 모양 — 이슈 #40.
 *
 * <h2>{@link #category} 가 {@code null} 일 수 있다</h2>
 * <p>계약이 {@code PlaceCategory} 를 <b>닫힌 enum</b>(12·14·28·32·38·39·vet·shop·trail)으로
 * 선언했는데, KTO 는 그 여섯 밖의 {@code contenttypeid} 를 줄 수 있다. 모르는 값을 그대로
 * 실으면 <b>계약을 깨는 응답</b>이 되고, 아무 값으로 눕히면 화면이 엉뚱한 아이콘을 그린다.
 *
 * <p>그래서 모르면 <b>필드를 생략</b>한다({@code JsonInclude.NON_NULL}). 앱은 이미
 * {@code petCatByType} 로 모르는 값을 "기타" 로 폴백하므로 화면이 깨지지 않는다.
 *
 * <p>{@link #contentTypeId} 는 KTO 값을 <b>그대로</b> 싣는다 — 계약이 자유 문자열이고,
 * 앱의 카테고리 필터가 이 값으로 비교한다.
 *
 * <h2>{@link #distM} 은 캐시에 안 들어간다</h2>
 * <p>거리는 <b>묻는 사람의 좌표</b>에 따라 달라진다. 셀 스냅샷은 셀 중심에서 받은 것이라
 * 그때의 거리를 그대로 실으면 같은 셀의 모든 사용자가 같은 거리를 본다. 서빙 시점에
 * 사용자 실좌표로 다시 계산한다.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PlaceDto(
        String contentId,
        String title,
        String source,
        String category,
        String contentTypeId,
        double lat,
        double lng,
        String addr,
        String tel,
        String image,
        Double distM) {

    /** 이 프록시가 내보내는 유일한 출처. {@code vet}/{@code shop}/{@code trail} 은 미구현이다. */
    public static final String SOURCE_KTO = "kto";

    /** 거리를 채운 사본. 캐시에서 꺼낸 뒤 서빙 직전에 부른다. */
    public PlaceDto withDistance(double meters) {
        return new PlaceDto(contentId, title, source, category, contentTypeId,
                lat, lng, addr, tel, image, meters);
    }
}

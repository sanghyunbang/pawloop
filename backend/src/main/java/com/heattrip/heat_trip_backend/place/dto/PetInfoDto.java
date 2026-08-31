package com.heattrip.heat_trip_backend.place.dto;

/**
 * 계약의 {@code PlaceDetail.petInfo} — 이슈 #40.
 *
 * <p>KTO {@code detailPetTour2} 가 주는 값이고 <b>대부분 자유 텍스트</b>다. 파싱하지 않고
 * 그대로 옮긴다 — 형식이 없는 값을 구조화하려 들면 우리가 만든 규칙이 KTO 가 바꾸는 순간
 * 조용히 틀려진다.
 *
 * <p><b>객체 자체는 항상 있다.</b> 세 필드가 각각 {@code null} 일 수 있을 뿐이다 —
 * 계약이 {@code petInfo} 를 nullable 로 선언하지 않았으므로 서버가 그것을 맞춘다.
 */
public record PetInfoDto(String acmpyPsblCpam, String acmpyNeedMtr, String etcAcmpyInfo) {

    /** 아직 못 받았거나 KTO 가 안 준 상태. */
    public static PetInfoDto empty() {
        return new PetInfoDto(null, null, null);
    }
}

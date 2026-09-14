package com.heattrip.heat_trip_backend.dog;

/**
 * 다른 모듈이 아이에 대해 알아도 되는 최소 — 크기와 나이대 — 이슈 #486.
 *
 * <p>AI 주간 요약이 모델에 보내는 것은 이 둘뿐이다. 이름 · 품종 · 사진은 여기 없다 — 개인정보처리방침
 * v1.8 의 "AI 주간 요약" 항목이 그 목록이고, 이 레코드가 넓어지면 그 문서도 같이 넓어져야 한다.
 *
 * <p>{@code dog.entity.DogSize} 를 밖으로 내지 않으려고 크기는 계약의 문자열({@code small} ·
 * {@code medium} · {@code large})이다 — 모듈 경계(#97 · #98).
 *
 * @param sizeKey   {@code small} · {@code medium} · {@code large}
 * @param ageMonths 개월. 생일이 없으면 null
 */
public record DogProfileView(String sizeKey, Integer ageMonths) {
}

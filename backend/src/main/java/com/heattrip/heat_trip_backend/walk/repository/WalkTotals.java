package com.heattrip.heat_trip_backend.walk.repository;

/**
 * 전체 기간 집계 한 줄 — 이슈 #145.
 *
 * <p>{@code Object[]} 로 받지 않는 이유: Spring Data 가 다중 컬럼 집계를 그 타입으로
 * 돌려주지 않아 {@link ClassCastException} 이 났다(실측 — 통계 경로가 500 이었다).
 * 생성자 표현식으로 받으면 타입이 컴파일 시점에 맞춰지고, 무엇보다 <b>어느 자리가 무엇인지</b>
 * 이름으로 읽힌다.
 *
 * @param distanceM 거리 합(m). 한 건도 없으면 {@code coalesce} 가 0 을 준다
 * @param count     건수
 * @param durationS 시간 합(초)
 */
public record WalkTotals(Long distanceM, Long count, Long durationS) {

    public long meters() {
        return distanceM == null ? 0 : distanceM;
    }

    public int walks() {
        return count == null ? 0 : count.intValue();
    }

    public long seconds() {
        return durationS == null ? 0 : durationS;
    }
}

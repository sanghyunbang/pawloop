package com.heattrip.heat_trip_backend.schedule;

import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * "어떤 일정이 케어인가" — 이슈 #420.
 *
 * <h2>왜 통합 테스트로는 부족한가</h2>
 * <p>{@code ScheduleIntegrationTest} 가 "미용·목욕·사료·그 밖은 케어 기록을 안 남긴다" 를
 * 이미 재고 있다. 그런데 <b>되돌려 보니 빨간불이 안 났다.</b>
 *
 * <p>이유는 방어가 <b>둘</b>이기 때문이다 — {@link ScheduleKind#careWire} 가 {@code null} 을
 * 주는 것이 첫째고, 설령 {@code "groom"} 을 주더라도 {@code CareType.of} 가 그 값을 모르는
 * 종류라고 거절하는 것이 둘째다. 통합 테스트는 결과만 보므로 둘을 구별하지 못한다.
 *
 * <p>그래서 첫째를 여기서 <b>직접</b> 잰다. 둘 다 있는 것은 좋은 일이지만, 하나가 사라져도
 * 아무도 모르는 것은 좋은 일이 아니다.
 */
class ScheduleKindTest {

    @Test
    @DisplayName("산책·병원·투약만 케어로 이어진다 — 그 값은 care_log 의 어휘와 같다")
    void onlyThreeKindsMapToCare() {
        assertThat(ScheduleKind.WALK.careWire()).isEqualTo("walk");
        assertThat(ScheduleKind.VET.careWire()).isEqualTo("vet");
        assertThat(ScheduleKind.MED.careWire()).isEqualTo("med");
    }

    @Test
    @DisplayName("미용·목욕·사료·그 밖은 케어가 아니다 — care_log 의 CHECK 가 받는 일곱에 없다")
    void theOtherFourAreNotCare() {
        assertThat(ScheduleKind.GROOM.careWire()).isNull();
        assertThat(ScheduleKind.BATH.careWire()).isNull();
        assertThat(ScheduleKind.FOOD.careWire()).isNull();
        assertThat(ScheduleKind.ETC.careWire()).isNull();
    }

    @Test
    @DisplayName("케어로 이어지는 값은 wire 와 글자까지 같다 — 두 도메인이 공유하는 문자열이다")
    void careWireMatchesTheKindsOwnWire() {
        for (ScheduleKind kind : ScheduleKind.values()) {
            String care = kind.careWire();
            if (care != null) {
                assertThat(care)
                        .as("%s 가 자기 wire 와 다른 값을 케어로 내면, DB 의 CHECK 둘이 갈린다",
                                kind)
                        .isEqualTo(kind.wire());
            }
        }
    }
}

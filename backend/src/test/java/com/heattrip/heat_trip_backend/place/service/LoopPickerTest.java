package com.heattrip.heat_trip_backend.place.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** 후보 중 부탁한 길이에 가장 가까운 코스 고르기 — 이슈 #725. 순수 함수라 컨텍스트 없이 잰다. */
class LoopPickerTest {

    private static OrsRoutingClient.Loop loop(double distanceM) {
        return new OrsRoutingClient.Loop(distanceM, distanceM / 1.25,
                List.of(new double[] {127.03, 37.54}, new double[] {127.04, 37.55}, new double[] {127.03, 37.54}));
    }

    @Test
    @DisplayName("가장 가까운 것을 고른다 — 2km 부탁에 5,478 · 2,130 · 1,600 이면 2,130")
    void picksTheClosest() {
        Optional<OrsRoutingClient.Loop> best = LoopPicker.pick(List.of(loop(5478), loop(2130), loop(1600)), 2000);

        assertThat(best).isPresent();
        assertThat(best.get().distanceM()).isEqualTo(2130);
    }

    @Test
    @DisplayName("두 배 넘게 어긋나면 안 준다 — 2km 부탁에 5.5km 는 추천이 아니다")
    void rejectsWhenEvenTheBestIsTwiceOff() {
        assertThat(LoopPicker.pick(List.of(loop(5478), loop(4200)), 2000)).isEmpty();
        assertThat(LoopPicker.pick(List.of(loop(3900)), 2000)).as("1,900 어긋남은 두 배 안이다").isPresent();
    }

    @Test
    @DisplayName("후보가 없거나 선이 두 점도 안 되면 빈 값")
    void emptyOrDegenerateCandidates() {
        assertThat(LoopPicker.pick(List.of(), 2000)).isEmpty();
        OrsRoutingClient.Loop onePoint = new OrsRoutingClient.Loop(2000, 1600, List.of(new double[] {127.03, 37.54}));
        assertThat(LoopPicker.pick(List.of(onePoint), 2000)).isEmpty();
    }
}

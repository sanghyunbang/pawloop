package com.heattrip.heat_trip_backend.place.service;

import java.util.List;
import java.util.Optional;

/**
 * 후보 여럿 중 부탁한 길이에 가장 가까운 코스 하나 — 이슈 #725. 순수 함수라 컨텍스트 없이 잰다.
 *
 * <p>왜 고르나: ORS 의 왕복은 seed 마다 모양이 달라 2km 를 부탁해도 5.5km 가 온다(실측). 그것을
 * "2km 코스" 라고 내보내면 카드가 거짓말을 한다. 그래서 몇 개 받아 가장 가까운 것을 고르고,
 * 그래도 <b>두 배 넘게</b> 어긋나면 추천하지 않는다 — 없는 편이 틀린 것보다 낫다.
 */
final class LoopPicker {

    private LoopPicker() {
    }

    static Optional<OrsRoutingClient.Loop> pick(List<OrsRoutingClient.Loop> candidates, int targetM) {
        OrsRoutingClient.Loop best = null;
        double bestDeviation = Double.MAX_VALUE;
        for (OrsRoutingClient.Loop candidate : candidates) {
            if (candidate == null || candidate.lngLat() == null || candidate.lngLat().size() < 2) {
                continue;
            }
            double deviation = Math.abs(candidate.distanceM() - targetM);
            if (deviation < bestDeviation) {
                bestDeviation = deviation;
                best = candidate;
            }
        }
        if (best == null || bestDeviation > targetM) {
            return Optional.empty();
        }
        return Optional.of(best);
    }
}

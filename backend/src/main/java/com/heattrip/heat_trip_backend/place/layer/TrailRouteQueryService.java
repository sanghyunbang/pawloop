package com.heattrip.heat_trip_backend.place.layer;

import com.heattrip.heat_trip_backend.place.dto.TrailRouteDto;
import com.heattrip.heat_trip_backend.place.repository.TrailRouteRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/**
 * 계약의 {@code GET /api/places/trails/{courseId}/route} — 이슈 #291 · #619.
 *
 * <h2>출처가 둘이고, 줄 수 있는 것도 둘이다</h2>
 * <p>산책로는 두 곳에서 온다(#346). 각자 "이 길이 어디로 가는가" 에 답할 것이 다르다.
 *
 * <pre>
 *   두루누비   trail_route 표에 GPX 선  →  points 300개
 *   동네 길    자산에 경유지 이름들      →  waypoints 6개쯤
 * </pre>
 *
 * <p>예전에는 앞의 것만 답하고 동네 길은 <b>404</b> 였다. 앱도 그걸 알아서 아예 묻지 않았고
 * ({@code hasTrailRoute}), 그래서 사용자가 동네 길을 눌러도 <b>아무 일도 안 났다</b> —
 * 2026-09-17 에 사장님이 그렇게 신고했다(#619).
 *
 * <p>지금은 표를 먼저 보고, 없으면 자산에 묻는다. <b>줄 것이 있는데 404 를 줄 이유가 없다.</b>
 * 둘 다 없을 때만 빈 값이다.
 *
 * <h2>표를 먼저 보는 이유</h2>
 * <p>선이 있으면 선이 낫다 — 지도에 그려진 길은 이름 목록이 못 하는 말을 한다. 그리고 코스
 * 번호의 모양이 갈려 있어({@code T_CRS_…} 대 {@code lt…}) 둘이 같은 번호로 부딪히는 일은
 * 없다. 순서는 <b>더 나은 답을 먼저</b>라는 뜻이지 충돌 해결이 아니다.
 */
@Service
public class TrailRouteQueryService {

    private final TrailRouteRepository routes;
    private final LocalTrailAsset localTrails;

    public TrailRouteQueryService(TrailRouteRepository routes, LocalTrailAsset localTrails) {
        this.routes = routes;
        this.localTrails = localTrails;
    }

    @Transactional(readOnly = true)
    public Optional<TrailRouteDto> route(String courseId) {
        if (courseId == null || courseId.isBlank()) {
            return Optional.empty();
        }
        String id = courseId.strip();
        return routes.findById(id)
                .map(r -> TrailRouteDto.ofLine(
                        r.getCourseId(), r.getName(), r.getLengthM(), r.getPointCount(), r.getPayload()))
                .or(() -> localTrails.route(id));
    }
}

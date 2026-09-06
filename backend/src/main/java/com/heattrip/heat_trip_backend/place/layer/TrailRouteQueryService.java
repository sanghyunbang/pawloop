package com.heattrip.heat_trip_backend.place.layer;

import com.heattrip.heat_trip_backend.place.dto.TrailRouteDto;
import com.heattrip.heat_trip_backend.place.repository.TrailRouteRepository;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/** 계약의 {@code GET /api/places/trails/{courseId}/route} — 이슈 #291. */
@Service
public class TrailRouteQueryService {

    private final TrailRouteRepository routes;

    public TrailRouteQueryService(TrailRouteRepository routes) {
        this.routes = routes;
    }

    @Transactional(readOnly = true)
    public Optional<TrailRouteDto> route(String courseId) {
        if (courseId == null || courseId.isBlank()) {
            return Optional.empty();
        }
        return routes.findById(courseId.strip())
                .map(r -> new TrailRouteDto(r.getCourseId(), r.getName(), r.getLengthM(), r.getPointCount(), r.getPayload()));
    }
}

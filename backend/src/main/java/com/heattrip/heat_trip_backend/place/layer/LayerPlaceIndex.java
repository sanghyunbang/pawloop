package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.place.CatalogSource;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;
import com.heattrip.heat_trip_backend.place.repository.PlaceCatalogRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 레이어 한 벌을 <b>메모리에 객체로</b> 갖고 있는다 — {@code GET /api/places/nearby} 가 쓴다. 이슈 #291.
 *
 * <p>카탈로그 경로는 문자열을 그대로 옮기지만, 주변 조회는 거리를 재야 해서 점이 객체여야
 * 한다. 요청마다 2MB 를 파싱할 수는 없으므로 <b>ETag 가 바뀔 때만</b> 다시 읽는다 — 요청당
 * 비용은 PK 로 ETag 한 줄을 읽는 것뿐이다.
 *
 * <p>KTO 셀 스냅샷은 여기 없다. 그쪽은 좌표 격자로 잘려 있어 {@code CellSnapshotStore} 가 따로 읽는다.
 */
@Service
public class LayerPlaceIndex {

    private static final Logger log = LoggerFactory.getLogger(LayerPlaceIndex.class);

    private static final TypeReference<List<PlaceDto>> PLACE_LIST = new TypeReference<>() { };

    private record Cached(String etag, List<PlaceDto> places) { }

    private final PlaceCatalogRepository catalogs;
    private final ObjectMapper objectMapper;
    private final Map<CatalogSource, Cached> cache = new ConcurrentHashMap<>();

    public LayerPlaceIndex(PlaceCatalogRepository catalogs, ObjectMapper objectMapper) {
        this.catalogs = catalogs;
        this.objectMapper = objectMapper;
    }

    /** 이 출처의 점 전부. 한 벌이 없으면 빈 목록이다. */
    @Transactional(readOnly = true)
    public List<PlaceDto> places(CatalogSource source) {
        Optional<String> etag = catalogs.etagOf(source.id());
        if (etag.isEmpty()) {
            cache.remove(source);
            return List.of();
        }
        Cached cached = cache.get(source);
        if (cached != null && cached.etag().equals(etag.get())) {
            return cached.places();
        }
        Optional<PlaceCatalog> row = catalogs.findById(source.id());
        if (row.isEmpty() || row.get().getItemCount() == 0) {
            cache.remove(source);
            return List.of();
        }
        List<PlaceDto> parsed;
        try {
            parsed = List.copyOf(objectMapper.readValue(row.get().getPayload(), PLACE_LIST));
        } catch (Exception e) {
            // 우리가 쓴 JSON 이라 여기 오면 저장 경로가 깨진 것이다. 조용히 비우지 않고 남긴다.
            log.error("레이어 한 벌을 읽지 못했다 — source={}", source, e);
            return List.of();
        }
        cache.put(source, new Cached(row.get().getEtag(), parsed));
        return parsed;
    }

    /** 두 레이어를 합친 점 전부. */
    public List<PlaceDto> allLayers() {
        List<PlaceDto> local = places(CatalogSource.LOCALDATA);
        List<PlaceDto> trails = places(CatalogSource.DURUNUBI);
        if (trails.isEmpty()) {
            return local;
        }
        if (local.isEmpty()) {
            return trails;
        }
        List<PlaceDto> both = new java.util.ArrayList<>(local.size() + trails.size());
        both.addAll(local);
        both.addAll(trails);
        return both;
    }
}

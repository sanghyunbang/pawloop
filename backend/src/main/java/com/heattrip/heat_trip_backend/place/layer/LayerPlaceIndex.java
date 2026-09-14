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

    /**
     * KTO 를 뺀 레이어를 전부 합친 점 — <b>겹침을 정리한 뒤</b>의 것이다(#411).
     *
     * <p><b>출처를 손으로 세지 않는다.</b> 전에는 둘을 이름으로 적어 뒀는데, #346 이
     * 넷째({@link CatalogSource#LOCALTRAIL})를 더했을 때 여기를 안 고쳐서 자산 1,302개가
     * {@code place_catalog} 에는 담겼는데 카탈로그 응답에는 한 곳도 안 나왔다. 열거형이
     * 늘면 여기도 함께 는다.
     */
    public List<PlaceDto> allLayers() {
        return merged().layers();
    }

    private record MergedCache(String key, PlaceDedupe.Merged merged) { }

    private volatile MergedCache mergedCache;

    /**
     * 겹침을 정리한 한 벌 (#411) — 우리 자산(놀이터 · 동네 길)이 관광공사 · 두루누비 · 인허가
     * 항목과 같은 자리면 빠지고, 놀이터에 밀린 관광공사 항목은 놀이터를 옮겨 단 사본이 된다.
     * 규칙은 {@link PlaceDedupe} 에 있다.
     *
     * <p>출처 다섯의 ETag 가 하나라도 바뀔 때만 다시 만든다 — 요청당 비용은 ETag 다섯 줄을
     * 읽는 것뿐이다. 관광공사 한 벌(2MB 남짓)도 여기서 객체로 읽어 두는데, {@link #places}
     * 가 ETag 로 캐시하므로 하루 한 번(새벽 예열)이다.
     *
     * <p>어느 출처가 "우리 자산" 인지는 {@link CatalogSource#isAsset()} 이 말한다 — 이름을
     * 손으로 세지 않는다.
     */
    @Transactional(readOnly = true)
    public PlaceDedupe.Merged merged() {
        StringBuilder key = new StringBuilder();
        for (CatalogSource source : CatalogSource.values()) {
            key.append(catalogs.etagOf(source.id()).orElse("-")).append('|');
        }
        MergedCache cached = mergedCache;
        if (cached != null && cached.key().contentEquals(key)) {
            return cached.merged();
        }
        List<PlaceDto> kto = List.of();
        List<PlaceDto> others = new java.util.ArrayList<>();
        List<PlaceDto> ours = new java.util.ArrayList<>();
        for (CatalogSource source : CatalogSource.values()) {
            if (source == CatalogSource.KTO) {
                kto = places(source);
            } else if (source.isAsset()) {
                ours.addAll(places(source));
            } else {
                others.addAll(places(source));
            }
        }
        PlaceDedupe.Merged merged = PlaceDedupe.merge(kto, others, ours);
        if (merged.dropped() > 0) {
            log.info("겹치는 자리를 정리했다 — 우리 자산 {}곳을 뺐고, 관광공사 {}곳에 놀이터를 옮겨 달았다 (#411)",
                    merged.dropped(), merged.overrides().size());
        }
        mergedCache = new MergedCache(key.toString(), merged);
        return merged;
    }
}

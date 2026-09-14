package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.GeoDistance;
import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCell;
import com.heattrip.heat_trip_backend.place.layer.LayerPlaceIndex;
import com.heattrip.heat_trip_backend.place.layer.PlaceDedupe;

import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * 내 주변 반려동반 장소 — 이슈 #40. 계약의 {@code GET /api/places/nearby} 다.
 *
 * <h2>이 클래스가 지키는 순서</h2>
 * <ol>
 *   <li>좌표를 격자 셀로 접는다({@link GridCell}).</li>
 *   <li>그 셀의 스냅샷이 있으면 <b>먼저 답을 확보</b>한다.</li>
 *   <li>낡았고 예산이 있으면 갱신을 <b>시도</b>한다. 실패하면 2번 답을 그대로 준다.</li>
 *   <li>스냅샷이 아예 없고 갱신도 못 하면 빈 목록이다.</li>
 * </ol>
 *
 * <h2>오래된 답이 빈 지도보다 낫다</h2>
 * <p>스냅샷에 <b>만료가 없다.</b> {@code fetchedAt} 은 "갱신을 시도해도 되는가" 만 정하고,
 * 예산이 없으면 며칠 된 것도 그대로 준다. 만료를 두면 좌표를 훑는 요청이 며칠 이어졌을 때
 * 셀이 하나씩 사라지고 결국 <b>지도가 영구히 빈 화면</b>이 된다.
 *
 * <h2>거리는 서빙 시점에 계산한다</h2>
 * <p>스냅샷은 <b>셀 중심</b>에서 받은 것이라 KTO 가 준 {@code dist} 는 셀 중심 기준이다.
 * 그대로 실으면 같은 셀의 모든 사용자가 같은 거리를 본다 — 최대 1.4km 틀린다.
 * 그래서 캐시에는 거리를 안 넣고 서빙할 때 <b>묻는 사람의 좌표</b>로 다시 잰다.
 *
 * <h2>카테고리를 캐시 키에 안 넣는다</h2>
 * <p>넣으면 셀 하나가 카테고리 수만큼 캐시돼야 하고 셀당 콜이 최대 6배가 된다.
 * 상위집합을 한 번 받아 두고 <b>서버에서 거른다</b> — 앱도 이미 같은 필터를 화면에서 한다
 * ({@code explore_screen.dart} 의 {@code _filtered}).
 */
@Service
public class PlaceQueryService {

    /** 지구 반지름(m). 하버사인에 쓴다. */

    private final CellSnapshotStore snapshots;
    private final KtoApiClient kto;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final KtoBudgetProperties properties;
    private final LayerPlaceIndex layers;
    private final Clock clock;

    public PlaceQueryService(CellSnapshotStore snapshots,
                             KtoApiClient kto,
                             KtoCallBudget budget,
                             UpstreamGate gate,
                             KtoBudgetProperties properties,
                             LayerPlaceIndex layers,
                             Clock clock) {
        this.snapshots = snapshots;
        this.kto = kto;
        this.budget = budget;
        this.gate = gate;
        this.properties = properties;
        this.layers = layers;
        this.clock = clock;
    }

    /**
     * 이 좌표 주변의 장소를 거리순으로.
     *
     * @param radiusM  사용자가 요청한 반경. {@link GridCell#GUARANTEED_RADIUS_M} 이하여야
     *                 셀 안 어디서든 완전히 덮인다 — 계약이 그 값으로 상한을 건다
     * @param category KTO {@code contentTypeId} 또는 레이어 키({@code vet}·{@code shop}·{@code trail}).
     *                 {@code null} 이면 전부 — KTO 셀과 레이어 한 벌을 합친다(#291)
     */
    public List<PlaceDto> nearby(double lat, double lng, int radiusM, String category, int limit) {
        boolean layerOnly = category != null && PlaceDto.LAYER_SOURCES.contains(category);
        // 겹침을 정리한 한 벌 (#411) — 우리 자산이 관광공사 항목과 같은 자리면 빠져 있고,
        // 놀이터에 밀린 관광공사 항목은 놀이터를 옮겨 단 사본이 있다.
        PlaceDedupe.Merged merged = layers.merged();
        List<PlaceDto> pool = new ArrayList<>();
        Set<String> inCell = new HashSet<>();

        // 레이어 칩(vet·shop·trail·playground)이면 KTO 셀을 부르지 않는다 — 부르면 예산만 태운다.
        if (!layerOnly) {
            List<PlaceDto> ktoPlaces = ktoCell(lat, lng);
            if (ktoPlaces != null) {
                for (PlaceDto place : ktoPlaces) {
                    pool.add(merged.override(place));
                    inCell.add(place.contentId());
                }
            }
        }
        // 전체이거나 레이어 칩이면 레이어 한 벌도 본다. 전국이 메모리에 있고 거리는 여기서 잰다.
        if (category == null || layerOnly) {
            pool.addAll(merged.layers());
            // 옮겨 단 관광공사 항목은 KTO 셀에 없을 수 있다 — 셀은 KTO 주변 조회가 준 것이라 전국
            // 한 벌보다 좁다(일산 셀 19곳에 "일산호수공원 반려견놀이터" 가 없었다, 2026-09-14 실측).
            // 놀이터 칩은 셀을 부르지도 않는다. 셀에 이미 있으면(사본으로 바뀐 채) 다시 더하지 않는다.
            // 다른 레이어 칩(병원 · 산책로)에서는 아래 카테고리 비교가 걸러 낸다.
            for (PlaceDto copy : merged.overrides().values()) {
                if (!inCell.contains(copy.contentId())) {
                    pool.add(copy);
                }
            }
        }

        if (pool.isEmpty()) {
            // 스냅샷도 없고 갱신도 못 했다. 빈 목록이다 — 앱은 지금도 실패를 빈 목록으로
            // 다루므로 화면이 깨지지 않는다. 운영자는 kto_call_budget 과 로그로 본다.
            return List.of();
        }

        return within(pool, lat, lng, radiusM, category, limit);
    }

    /** KTO 셀 스냅샷. 없고 갱신도 못 했으면 {@code null}. */
    private List<PlaceDto> ktoCell(double lat, double lng) {
        GridCell cell = GridCell.of(lat, lng);
        Optional<PlaceCell> row = snapshots.find(cell);

        List<PlaceDto> places = row.flatMap(snapshots::read).orElse(null);

        if (places == null || shouldRefresh(row.orElse(null))) {
            List<PlaceDto> fresh = refresh(cell);
            if (fresh != null) {
                places = fresh;
            }
        }
        return places;
    }

    /**
     * 산책로({@code category=trail})는 반경을 안 보고 가까운 순 이만큼을 준다 — 2026-09-06 결정(#291).
     *
     * <p>코리아둘레길(해파랑·남파랑·서해랑·DMZ)은 해안·접경에만 있어 도심에서 8km 안은 늘 비었다.
     * 산책로는 "근처에 있는 곳" 이 아니라 "가는 곳" 이다. 앱의 {@code kTrailNearestLimit} 과 같은 수다 —
     * 기기 안 계산(A안)과 여기(B안)가 같은 답을 내야 한다.
     */
    static final int TRAIL_NEAREST_LIMIT = 20;

    /**
     * 반경·카테고리로 거르고 거리순으로 자른다. 산책로만 반경을 안 본다({@link #TRAIL_NEAREST_LIMIT}).
     */
    private static List<PlaceDto> within(List<PlaceDto> places, double lat, double lng,
                                         int radiusM, String category, int limit) {
        boolean trailsOnly = PlaceDto.SOURCE_TRAIL.equals(category);
        int cap = trailsOnly ? Math.min(limit, TRAIL_NEAREST_LIMIT) : limit;
        List<PlaceDto> out = new ArrayList<>();
        for (PlaceDto place : places) {
            if (category != null && !category.equals(place.categoryKey())) {
                continue;
            }
            double distance = GeoDistance.metersBetween(lat, lng, place.lat(), place.lng());
            if (!trailsOnly && distance > radiusM) {
                continue;
            }
            out.add(place.withDistance(distance));
        }
        out.sort(Comparator.comparingDouble(p -> p.distM() == null ? Double.MAX_VALUE : p.distM()));
        return out.size() > cap ? List.copyOf(out.subList(0, cap)) : out;
    }

    /**
     * 갱신을 <b>시도해도 되는가</b>. 만료가 아니다 — 위 javadoc 참조.
     *
     * <p>{@code null} 이면 행 자체가 없다는 뜻이라 시도해야 한다.
     */
    private boolean shouldRefresh(PlaceCell row) {
        if (row == null) {
            return true;
        }
        LocalDateTime now = LocalDateTime.now(clock);

        // 실패 직후에는 쉰다. 실패한 호출도 예산을 태우므로, 백오프가 없으면 KTO 가 아픈
        // 동안 예산이 순식간에 사라지고 회복된 뒤에 쓸 것이 남지 않는다.
        // 연속 실패가 쌓일수록 간격이 길어진다.
        if (row.getFailedAt() != null) {
            long backoff = (long) properties.getFailureBackoffMinutes() * Math.max(1, row.getFailStreak());
            if (row.getFailedAt().plusMinutes(backoff).isAfter(now)) {
                return false;
            }
        }

        return row.getFetchedAt().plusHours(properties.getCellRefreshHours()).isBefore(now);
    }

    /**
     * 셀 하나를 다시 받아 저장한다.
     *
     * @return 새 스냅샷. 예산이 없거나 남이 이미 받고 있거나 KTO 가 실패하면 {@code null}
     */
    private List<PlaceDto> refresh(GridCell cell) {
        String key = cell.latIdx() + ":" + cell.lngIdx();
        return gate.runIfOwner(key, () -> {
            // 예산이 먼저다. 이 문을 통과하지 못하면 호출 자체가 없다.
            if (!budget.tryAcquire(KtoPool.NEARBY, 1)) {
                return null;
            }

            KtoApiClient.Result<List<PlaceDto>> result =
                    kto.fetchNearby(cell.centerLat(), cell.centerLng());

            if (result instanceof KtoApiClient.Result.Failed<List<PlaceDto>> failed) {
                closeIfQuotaOrKey(failed.resultCode());
                snapshots.recordFailure(cell);
                return null;
            }

            List<PlaceDto> places = List.of();
            int totalCount = 0;
            if (result instanceof KtoApiClient.Result.Ok<List<PlaceDto>> ok) {
                places = ok.value();
                totalCount = ok.totalCount();
            }

            snapshots.store(cell, places, totalCount);
            return places;
        });
    }

    private void closeIfQuotaOrKey(String resultCode) {
        if (KtoApiClient.RESULT_QUOTA_EXCEEDED.equals(resultCode)
                || KtoApiClient.RESULT_KEY_NOT_REGISTERED.equals(resultCode)) {
            budget.closeForToday(KtoPool.NEARBY, "resultCode=" + resultCode);
        }
    }
}

package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCell;

import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

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
    private static final double EARTH_RADIUS_M = 6_371_000.0;

    private final CellSnapshotStore snapshots;
    private final KtoApiClient kto;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final KtoBudgetProperties properties;
    private final Clock clock;

    public PlaceQueryService(CellSnapshotStore snapshots,
                             KtoApiClient kto,
                             KtoCallBudget budget,
                             UpstreamGate gate,
                             KtoBudgetProperties properties,
                             Clock clock) {
        this.snapshots = snapshots;
        this.kto = kto;
        this.budget = budget;
        this.gate = gate;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * 이 좌표 주변의 장소를 거리순으로.
     *
     * @param radiusM  사용자가 요청한 반경. {@link GridCell#GUARANTEED_RADIUS_M} 이하여야
     *                 셀 안 어디서든 완전히 덮인다 — 계약이 그 값으로 상한을 건다
     * @param category KTO {@code contentTypeId}. {@code null} 이면 전부
     */
    public List<PlaceDto> nearby(double lat, double lng, int radiusM, String category, int limit) {
        GridCell cell = GridCell.of(lat, lng);
        Optional<PlaceCell> row = snapshots.find(cell);

        List<PlaceDto> places = row.flatMap(snapshots::read).orElse(null);

        if (places == null || shouldRefresh(row.orElse(null))) {
            List<PlaceDto> fresh = refresh(cell);
            if (fresh != null) {
                places = fresh;
            }
        }

        if (places == null) {
            // 스냅샷도 없고 갱신도 못 했다. 빈 목록이다 — 앱은 지금도 실패를 빈 목록으로
            // 다루므로 화면이 깨지지 않는다. 운영자는 kto_call_budget 과 로그로 본다.
            return List.of();
        }

        return within(places, lat, lng, radiusM, category, limit);
    }

    /** 반경·카테고리로 거르고 거리순으로 자른다. */
    private static List<PlaceDto> within(List<PlaceDto> places, double lat, double lng,
                                         int radiusM, String category, int limit) {
        List<PlaceDto> out = new ArrayList<>();
        for (PlaceDto place : places) {
            if (category != null && !category.equals(place.contentTypeId())) {
                continue;
            }
            double distance = haversineMeters(lat, lng, place.lat(), place.lng());
            if (distance > radiusM) {
                continue;
            }
            out.add(place.withDistance(distance));
        }
        out.sort(Comparator.comparingDouble(p -> p.distM() == null ? Double.MAX_VALUE : p.distM()));
        return out.size() > limit ? List.copyOf(out.subList(0, limit)) : out;
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

    /**
     * 두 좌표 사이의 거리(m).
     *
     * <p>KTO 가 준 {@code dist} 를 안 쓰는 이유는 위 javadoc 참조 — 그 값은 셀 중심 기준이다.
     */
    static double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}

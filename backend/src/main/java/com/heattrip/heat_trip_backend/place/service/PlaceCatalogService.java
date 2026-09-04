package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.KtoBudgetProperties;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 전국 반려동반 장소 한 벌 — 이슈 #273. 계약의 {@code GET /api/places/catalog} 다.
 *
 * <h2>이 경로가 존재하는 이유</h2>
 * <p>{@link PlaceQueryService} 는 좌표를 받는다. A안 빌드(완전 온디바이스)는 좌표를 서버로
 * 안 보내므로 그 길을 못 쓰고, 그러면 <b>지도의 장소 목록이 빈다</b>(#235 A4).
 *
 * <p>여기는 <b>요청에 아무것도 안 실린다.</b> 좌표도 지역 코드도 없다. 앱이 한 벌을 받아
 * 기기에 두고 거리 정렬을 기기에서 한다.
 *
 * <h2>{@link PlaceQueryService} 와 같은 순서, 같은 원칙</h2>
 * <ol>
 *   <li>저장된 한 벌이 있으면 <b>먼저 답을 확보</b>한다.</li>
 *   <li>낡았고 예산이 있으면 갱신을 <b>시도</b>한다. 실패하면 1번 답을 그대로 준다.</li>
 *   <li>한 벌이 아예 없고 갱신도 못 하면 빈 목록이다.</li>
 * </ol>
 *
 * <p><b>만료가 없다.</b> {@code fetchedAt} 은 "갱신을 시도해도 되는가" 만 정한다.
 * 만료를 두면 KTO 가 며칠 아플 때 지도가 <b>영구히 빈 화면</b>이 된다.
 *
 * <h2>첫 요청이 비싸다 — 알고 넣는다</h2>
 * <p>한 벌이 없거나 낡았을 때, <b>그 요청을 한 사람이</b> 10번의 KTO 호출을 기다린다
 * (10~20초). {@link UpstreamGate} 가 단일화하므로 그 사이 다른 사람은 기다리지 않고
 * 옛 한 벌을 받지만, 처음 한 사람은 기다린다.
 *
 * <p>{@code nearby} 도 같은 모양이고(한 사람이 셀 하나를 데운다) 다만 이쪽은 10배 길다.
 * 부팅 시 예열이나 스케줄 갱신으로 없앨 수 있는데, 그건 이 이슈의 범위가 아니라
 * <b>별건으로 남긴다</b> — 여기서 붙이면 테스트·CI 가 뜰 때마다 KTO 를 부른다.
 */
@Service
public class PlaceCatalogService {

    private static final Logger log = LoggerFactory.getLogger(PlaceCatalogService.class);

    /** {@link UpstreamGate} 에 쓰는 키. 한 벌이 하나라 상수다. */
    private static final String GATE_KEY = "catalog";

    /**
     * 한 번 데울 때 넘기지 않는 페이지 수.
     *
     * <p>예산({@code catalogMaxCallsPerDay}) 이 이미 상한이라 이것은 <b>이중 방어</b>다.
     * KTO 가 {@code totalCount} 를 터무니없이 크게 주면 예산이 한 번에 다 타는데,
     * 그러면 그날 지도가 죽는다. 예산은 "하루" 를 지키고 이것은 "한 번" 을 지킨다.
     */
    static final int MAX_PAGES = 30;

    private final CatalogSnapshotStore snapshots;
    private final KtoApiClient kto;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final KtoBudgetProperties properties;
    private final Clock clock;

    public PlaceCatalogService(CatalogSnapshotStore snapshots,
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
     * 서빙할 한 벌.
     *
     * @return 저장된 행. 한 벌도 없고 받아 오지도 못했으면 비어 있다
     */
    public Optional<PlaceCatalog> catalog() {
        Optional<PlaceCatalog> row = snapshots.find();

        if (row.isEmpty() || shouldRefresh(row.get())) {
            Optional<PlaceCatalog> fresh = refresh();
            if (fresh.isPresent()) {
                return fresh;
            }
        }

        // 자리표시(실패해서 만들어 둔 빈 행)는 답이 아니다. 그것을 200 으로 주면
        // 앱이 "전국에 장소가 0곳" 이라는 답을 캐시한다.
        return row.filter(c -> c.getItemCount() > 0);
    }

    /**
     * 갱신을 <b>시도해도 되는가</b>. 만료가 아니다 — 위 javadoc 참조.
     *
     * <p>주기는 {@code cellRefreshHours} 를 <b>같이 쓴다.</b> 둘 다 같은 KTO 데이터를
     * 보고, 신선도 요구가 다를 이유가 없다. 다른 값이 필요해지면 그때 나눈다 —
     * 지금 나누면 아무도 안 돌리는 손잡이가 하나 더 생긴다.
     */
    private boolean shouldRefresh(PlaceCatalog row) {
        LocalDateTime now = LocalDateTime.now(clock);

        // 실패 직후에는 쉰다. 실패한 호출도 예산을 태우므로, 백오프가 없으면 KTO 가 아픈
        // 동안 예산이 순식간에 사라지고 회복된 뒤에 쓸 것이 남지 않는다.
        if (row.getFailedAt() != null) {
            long backoff = (long) properties.getFailureBackoffMinutes()
                    * Math.max(1, row.getFailStreak());
            if (row.getFailedAt().plusMinutes(backoff).isAfter(now)) {
                return false;
            }
        }

        return row.getFetchedAt().plusHours(properties.getCellRefreshHours()).isBefore(now);
    }

    /**
     * 한 벌을 페이지 단위로 다 받아 저장한다.
     *
     * <p><b>중간에 실패하면 아무것도 저장하지 않는다.</b> 반쪽짜리를 저장하면 지도에서
     * 장소가 조용히 사라지고, 그 상태가 캐시 수명만큼 굳는다. 옛 한 벌이 반쪽보다 낫다.
     *
     * @return 새 한 벌. 예산이 없거나 남이 이미 받고 있거나 KTO 가 실패하면 비어 있다
     */
    private Optional<PlaceCatalog> refresh() {
        Optional<PlaceCatalog> result = gate.runIfOwner(GATE_KEY, () -> {
            List<PlaceDto> all = new ArrayList<>();
            int totalCount = -1;

            for (int page = 1; page <= MAX_PAGES; page++) {
                // 예산이 먼저다. 이 문을 통과하지 못하면 호출 자체가 없다.
                if (!budget.tryAcquire(KtoPool.CATALOG, 1)) {
                    log.warn("카탈로그 예산이 없다 — {}페이지에서 멈춘다. 옛 한 벌을 계속 준다.", page);
                    return Optional.<PlaceCatalog>empty();
                }

                KtoApiClient.Result<List<PlaceDto>> result0 = kto.fetchCatalogPage(page);

                if (result0 instanceof KtoApiClient.Result.Failed<List<PlaceDto>> failed) {
                    closeIfQuotaOrKey(failed.resultCode());
                    snapshots.recordFailure();
                    return Optional.<PlaceCatalog>empty();
                }
                if (!(result0 instanceof KtoApiClient.Result.Ok<List<PlaceDto>> ok)) {
                    // Empty 다 — KTO 가 정상이라고 답했는데 내용이 없다. 더 볼 페이지가 없다.
                    break;
                }
                if (totalCount < 0) {
                    totalCount = ok.totalCount();
                }
                if (ok.value().isEmpty()) {
                    break;
                }
                all.addAll(ok.value());

                if (all.size() >= totalCount) {
                    break;
                }
            }

            return snapshots.store(all, Math.max(totalCount, 0));
        });

        return result == null ? Optional.empty() : result;
    }

    private void closeIfQuotaOrKey(String resultCode) {
        if (KtoApiClient.RESULT_QUOTA_EXCEEDED.equals(resultCode)
                || KtoApiClient.RESULT_KEY_NOT_REGISTERED.equals(resultCode)) {
            budget.closeForToday(KtoPool.CATALOG, "resultCode=" + resultCode);
        }
    }
}

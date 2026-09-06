package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.CatalogSource;
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
 * <h2>첫 요청이 비쌌다 — 새벽에 미리 받는다</h2>
 * <p>한 벌이 없거나 낡았을 때, <b>그 요청을 한 사람이</b> 10번의 KTO 호출을 기다렸다
 * (실측 16초). {@link UpstreamGate} 가 단일화하므로 그 사이 다른 사람은 옛 한 벌을 바로
 * 받지만, 처음 한 사람은 기다렸다 — 24시간마다 한 명씩, 매일.
 *
 * <p>그래서 {@link PlaceCatalogWarmupScheduler} 가 매일 새벽에 {@link #warmUp()} 을 부른다
 * (#279). 서버가 켜질 때 받는 것으로는 안 된다 — 그건 배포한 날만 해결하고, 서버가 며칠
 * 안 꺼지면 다음 날부터 또 첫 사람이 기다린다. 테스트·CI 에서는 프로퍼티로 꺼져 있다.
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
     * 사용자가 오기 전에 한 벌을 데운다 — {@link PlaceCatalogWarmupScheduler} 가 새벽에 부른다.
     *
     * <p>{@link #catalog()} 와 같은 길을 지난다. 낡지 않았으면 아무것도 안 하고, 낡았으면
     * 받아서 저장한다. 같은 예산 풀({@link KtoPool#CATALOG})과 같은 백오프를 쓴다 — 예열이
     * 사용자 요청보다 특권을 갖지 않는다.
     *
     * <p>결과를 <b>로그로만</b> 남긴다. 실패해도 던지지 않는다 — 스케줄 잡이 예외로 죽으면
     * 다음 날 아무도 그 사실을 모른다.
     */
    public void warmUp() {
        Optional<PlaceCatalog> row = catalog();
        if (row.isEmpty()) {
            log.warn("카탈로그 예열 실패 — 한 벌이 없다. 다음 사용자 요청이 다시 시도한다.");
            return;
        }
        log.info("카탈로그 예열 — {}곳, fetchedAt={}", row.get().getItemCount(), row.get().getFetchedAt());
    }

    /** 앱에 나가는 본문과 그 ETag — 세 출처를 이어 붙인 것이다(#291). */
    public record Served(String payload, String etag) { }

    /**
     * 계약의 {@code GET /api/places/catalog} 본문 — <b>KTO 한 벌 뒤에 인허가·두루누비 한 벌을
     * 이어 붙인다</b>(#291). 앱은 출처가 몇인지 모르고 배열 하나를 받는다.
     *
     * <p>KTO 한 벌이 없으면 <b>비어 있다</b> — 레이어만 주면 앱이 "전국에 병원뿐인 한 벌" 을
     * 캐시하고, KTO 가 회복해도 ETag 가 바뀔 때까지 지도의 대부분이 빈다. 반대로 레이어가
     * 없는 것은 정상이다(활용신청 전·첫 적재 전) — KTO 만 나간다.
     *
     * <p>ETag 는 이어 붙인 벌들의 ETag 를 다시 해시한 것이다. 어느 한 벌이 바뀌면 값이 바뀌고,
     * 셋 다 그대로면 그대로다. 한 벌뿐이면 그 행의 ETag 그대로라 #273 과 바이트까지 같다.
     */
    public Optional<Served> serve() {
        Optional<PlaceCatalog> kto = catalog();
        if (kto.isEmpty()) {
            return Optional.empty();
        }
        List<PlaceCatalog> rows = new ArrayList<>();
        rows.add(kto.get());
        for (CatalogSource layer : List.of(CatalogSource.LOCALDATA, CatalogSource.DURUNUBI)) {
            snapshots.find(layer).filter(r -> r.getItemCount() > 0).ifPresent(rows::add);
        }
        if (rows.size() == 1) {
            return Optional.of(new Served(kto.get().getPayload(), kto.get().getEtag()));
        }
        return Optional.of(new Served(
                CatalogPayloads.concat(rows.stream().map(PlaceCatalog::getPayload).toList()),
                CatalogPayloads.combinedEtag(rows.stream().map(PlaceCatalog::getEtag).toList())));
    }

    /**
     * 서빙할 KTO 한 벌.
     *
     * @return 저장된 행. 한 벌도 없고 받아 오지도 못했으면 비어 있다
     */
    public Optional<PlaceCatalog> catalog() {
        Optional<PlaceCatalog> row = snapshots.find(CatalogSource.KTO);

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
                    snapshots.recordFailure(CatalogSource.KTO);
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

            return snapshots.store(CatalogSource.KTO, all, Math.max(totalCount, 0));
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

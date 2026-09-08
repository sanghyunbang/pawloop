package com.heattrip.heat_trip_backend.place.layer;

import com.fasterxml.jackson.databind.JsonNode;
import com.heattrip.heat_trip_backend.place.CatalogSource;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;
import com.heattrip.heat_trip_backend.place.entity.TrailRoute;
import com.heattrip.heat_trip_backend.place.repository.TrailRouteRepository;
import com.heattrip.heat_trip_backend.place.service.CatalogSnapshotStore;
import com.heattrip.heat_trip_backend.place.service.KtoApiClient;
import com.heattrip.heat_trip_backend.place.service.KtoCallBudget;
import com.heattrip.heat_trip_backend.place.service.KtoPool;
import com.heattrip.heat_trip_backend.place.service.UpstreamGate;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * 공공데이터 레이어 둘을 받아 {@code place_catalog} 에 한 벌씩 놓는다 — 이슈 #291.
 *
 * <ul>
 *   <li>{@link CatalogSource#LOCALDATA} — 동물병원·동물판매업. 페이지를 다 받아 좌표를 바꾸고
 *       점 목록으로 저장한다.</li>
 *   <li>{@link CatalogSource#DURUNUBI} — 걷기여행길. 코스 목록을 받고, 코스마다 GPX 를 받아
 *       <b>선은 {@code trail_route} 에, 시작점은 카탈로그에</b> 나눠 담는다.</li>
 * </ul>
 *
 * <h2>KTO 카탈로그와 같은 원칙</h2>
 * <ul>
 *   <li><b>중간에 실패하면 아무것도 저장하지 않는다.</b> 옛 한 벌이 반쪽보다 낫다.</li>
 *   <li>예산이 먼저다. {@link KtoCallBudget} 의 문을 못 지나면 호출 자체가 없다.</li>
 *   <li>키 미등록(30)·한도 초과(22)를 받으면 그 풀을 오늘치 닫는다. 활용신청이 안 된 API 를
 *       하루 종일 두드리지 않는다.</li>
 *   <li>{@link UpstreamGate} 로 한 번에 하나만 돈다 — 스케줄러와 기동 예열이 겹칠 수 있다.</li>
 * </ul>
 *
 * <p>트랜잭션을 걸지 않는다. 외부 호출 사이에 DB 커넥션을 붙들면 안 된다 — 저장은
 * {@link CatalogSnapshotStore}·{@link TrailRouteRepository} 가 각자 짧게 연다.
 */
@Service
public class LayerCatalogService {

    private static final Logger log = LoggerFactory.getLogger(LayerCatalogService.class);

    static final String GATE_LOCALDATA = "layer:localdata";
    static final String GATE_DURUNUBI = "layer:durunubi";

    private final CatalogSnapshotStore snapshots;
    private final LocalDataApiClient localData;
    private final DurunubiApiClient durunubi;
    private final GpxFetcher gpx;
    private final TrailRouteRepository routes;
    private final Tm5174 tm;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final LayerCatalogProperties properties;
    private final LocalTrailAsset localTrails;
    private final Clock clock;

    public LayerCatalogService(CatalogSnapshotStore snapshots,
                               LocalDataApiClient localData,
                               DurunubiApiClient durunubi,
                               GpxFetcher gpx,
                               TrailRouteRepository routes,
                               Tm5174 tm,
                               KtoCallBudget budget,
                               UpstreamGate gate,
                               LayerCatalogProperties properties,
                               LocalTrailAsset localTrails,
                               Clock clock) {
        this.snapshots = snapshots;
        this.localData = localData;
        this.durunubi = durunubi;
        this.gpx = gpx;
        this.routes = routes;
        this.tm = tm;
        this.budget = budget;
        this.gate = gate;
        this.properties = properties;
        this.localTrails = localTrails;
        this.clock = clock;
    }

    /** 셋 다 시도한다. 하나가 실패해도 나머지는 간다 — 서로 다른 출처다. */
    public void refreshAll() {
        refreshLocalData();
        refreshDurunubi();
        refreshLocalTrails();
    }

    /**
     * 동네 길을 자산에서 담는다 — 이슈 #346. <b>외부를 안 부른다.</b>
     *
     * <p>원본(전국길관광정보표준데이터)의 갱신주기가 "연간" 이라 저장소에 넣어 둔 파일을
     * 읽는다. 그래서 예산도 게이트도 안 쓴다 — 실패할 외부가 없다.
     *
     * <p>여기가 없으면 산책로 칩에 코리아둘레길만 남는다. 서울숲에서 가장 가까운 코스가
     * 19.7km 밖 DMZ 18km 코스였다(#328 실측).
     */
    public Optional<PlaceCatalog> refreshLocalTrails() {
        List<PlaceDto> places = localTrails.load();
        if (places.isEmpty()) {
            // 자산이 없거나 깨졌다. 지난 한 벌을 지우지 않는다 — 빈 한 벌로 덮으면
            // 그 순간부터 동네 길이 사라진다.
            log.warn("동네 길 자산이 비었다 — 지난 한 벌을 그대로 둔다");
            return Optional.empty();
        }
        return snapshots.store(CatalogSource.LOCALTRAIL, places, places.size());
    }

    /** 레이어 한 벌이 없거나 {@code refreshDays} 보다 오래됐는가 — 기동 예열과 스케줄러가 본다. */
    public boolean needsRefresh() {
        return isMissingOrStale(CatalogSource.LOCALDATA)
                || isMissingOrStale(CatalogSource.DURUNUBI)
                || isMissingOrStale(CatalogSource.LOCALTRAIL);
    }

    boolean isMissingOrStale(CatalogSource source) {
        Optional<PlaceCatalog> row = snapshots.find(source);
        if (row.isEmpty() || row.get().getItemCount() == 0) {
            return true;
        }
        return row.get().getFetchedAt().plusDays(properties.getRefreshDays()).isBefore(LocalDateTime.now(clock));
    }

    // ─────────────────────────── 인허가 ───────────────────────────

    /**
     * 동물병원·동물판매업을 다 받아 한 벌로 저장한다.
     *
     * @return 새 한 벌. 예산이 없거나 남이 받고 있거나 API 가 실패하면 비어 있다
     */
    public Optional<PlaceCatalog> refreshLocalData() {
        Optional<PlaceCatalog> result = gate.runIfOwner(GATE_LOCALDATA, () -> {
            List<PlaceDto> all = new ArrayList<>();
            int total = 0;
            int skipped = 0;

            for (LocalDataBiz biz : LocalDataBiz.values()) {
                int bizTotal = -1;
                int received = 0;
                for (int page = 1; page <= properties.getLocaldataMaxPages(); page++) {
                    if (!budget.tryAcquire(KtoPool.LOCALDATA, 1)) {
                        log.warn("인허가 예산이 없다 — {} {}페이지에서 멈춘다. 옛 한 벌을 계속 준다.", biz, page);
                        return Optional.<PlaceCatalog>empty();
                    }
                    KtoApiClient.Result<List<JsonNode>> result0 = localData.fetchPage(biz, page);
                    if (result0 instanceof KtoApiClient.Result.Failed<List<JsonNode>> failed) {
                        closeIfQuotaOrKey(KtoPool.LOCALDATA, failed.resultCode());
                        snapshots.recordFailure(CatalogSource.LOCALDATA);
                        return Optional.<PlaceCatalog>empty();
                    }
                    if (!(result0 instanceof KtoApiClient.Result.Ok<List<JsonNode>> ok)) {
                        break; // Empty — 더 볼 페이지가 없다
                    }
                    if (bizTotal < 0) {
                        bizTotal = ok.totalCount();
                    }
                    received += ok.value().size();
                    for (JsonNode item : ok.value()) {
                        Optional<PlaceDto> place = LocalDataPlaceMapper.toPlace(item, biz, tm);
                        if (place.isPresent()) {
                            all.add(place.get());
                        } else {
                            skipped++;
                        }
                    }
                    if (ok.value().size() < properties.getLocaldataPageSize()
                            || (bizTotal >= 0 && received >= bizTotal)) {
                        break;
                    }
                }
                total += Math.max(bizTotal, 0);
            }

            log.info("인허가 레이어 — 담은 곳 {} · 좌표 없음 등으로 건너뜀 {} · API 전체 {}", all.size(), skipped, total);
            // 전체 수에서 못 담는 행을 뺀다 — 좌표 없는 행은 다시 받아도 못 담으므로 '잘렸다'가 아니다.
            // 실측(#291)에서 8,110 중 354 가 그랬고, 다 받았는데도 경고가 울렸다.
            return snapshots.store(CatalogSource.LOCALDATA, all, Math.max(total - skipped, 0));
        });
        return result == null ? Optional.empty() : result;
    }

    // ─────────────────────────── 두루누비 ───────────────────────────

    /**
     * 걷기여행길 코스를 다 받아, 선은 {@code trail_route} 에 시작점은 카탈로그에 담는다.
     *
     * <p>이미 {@code refreshDays} 안에 받은 코스의 GPX 는 다시 받지 않는다. GPX 는 예산에
     * 안 잡히지만 2,000 파일이다.
     */
    public Optional<PlaceCatalog> refreshDurunubi() {
        Optional<PlaceCatalog> result = gate.runIfOwner(GATE_DURUNUBI, () -> {
            List<DurunubiApiClient.Course> courses = new ArrayList<>();
            int total = -1;

            for (int page = 1; page <= properties.getDurunubiMaxPages(); page++) {
                if (!budget.tryAcquire(KtoPool.DURUNUBI, 1)) {
                    log.warn("두루누비 예산이 없다 — {}페이지에서 멈춘다. 옛 한 벌을 계속 준다.", page);
                    return Optional.<PlaceCatalog>empty();
                }
                KtoApiClient.Result<List<DurunubiApiClient.Course>> result0 = durunubi.fetchCoursePage(page);
                if (result0 instanceof KtoApiClient.Result.Failed<List<DurunubiApiClient.Course>> failed) {
                    closeIfQuotaOrKey(KtoPool.DURUNUBI, failed.resultCode());
                    snapshots.recordFailure(CatalogSource.DURUNUBI);
                    return Optional.<PlaceCatalog>empty();
                }
                if (!(result0 instanceof KtoApiClient.Result.Ok<List<DurunubiApiClient.Course>> ok)) {
                    break;
                }
                if (total < 0) {
                    total = ok.totalCount();
                }
                courses.addAll(ok.value());
                if (ok.value().size() < properties.getDurunubiPageSize()
                        || (total >= 0 && courses.size() >= total)) {
                    break;
                }
            }

            LocalDateTime now = LocalDateTime.now(clock);
            Set<String> fresh = new HashSet<>(routes.courseIdsFetchedSince(now.minusDays(properties.getRefreshDays())));
            List<PlaceDto> places = new ArrayList<>();
            List<TrailRoute> pending = new ArrayList<>();
            int fetched = 0;
            int failedGpx = 0;

            for (DurunubiApiClient.Course course : courses) {
                TrailRoute route = null;
                if (fresh.contains(course.courseId())) {
                    route = routes.findById(course.courseId()).orElse(null);
                }
                if (route == null) {
                    if (fetched >= properties.getGpxMaxPerRun()) {
                        log.warn("GPX 상한({})에 닿았다 — 남은 코스는 다음 적재로 미룬다", properties.getGpxMaxPerRun());
                        break;
                    }
                    fetched++;
                    route = fetchRoute(course, now).orElse(null);
                    if (route == null) {
                        failedGpx++;
                        continue;
                    }
                    pending.add(route);
                    if (pending.size() >= 100) {
                        routes.saveAll(pending);
                        pending.clear();
                    }
                }
                places.add(new PlaceDto(
                        PlaceDto.SOURCE_TRAIL + ":" + course.courseId(),
                        course.name(),
                        PlaceDto.SOURCE_TRAIL,
                        PlaceDto.SOURCE_TRAIL,
                        null,
                        route.getStartLat(),
                        route.getStartLng(),
                        course.sigun() == null ? "" : course.sigun(),
                        null,
                        null,
                        null,
                        course.summary()));
            }
            if (!pending.isEmpty()) {
                routes.saveAll(pending);
            }

            log.info("두루누비 레이어 — 코스 {} · GPX 새로 받음 {} · 못 받음 {} · 담은 곳 {}",
                    courses.size(), fetched, failedGpx, places.size());
            // GPX 를 못 받은 코스는 전체 수에서도 뺀다 — 위 '못 받음' 이 그 수다. 상한에 걸려 미룬 코스만 '잘렸다'다.
            return snapshots.store(CatalogSource.DURUNUBI, places, Math.max(Math.max(total, 0) - failedGpx, 0));
        });
        return result == null ? Optional.empty() : result;
    }

    private Optional<TrailRoute> fetchRoute(DurunubiApiClient.Course course, LocalDateTime now) {
        Optional<String> xml = gpx.fetch(course.gpxUrl());
        if (xml.isEmpty()) {
            return Optional.empty();
        }
        List<double[]> points;
        try {
            points = GpxParser.trackPoints(xml.get());
        } catch (Exception e) {
            log.warn("GPX 를 읽지 못했다 — course={} ({})", course.courseId(), e.getClass().getSimpleName());
            return Optional.empty();
        }
        if (points.size() < 2) {
            return Optional.empty();
        }
        double length = GpxParser.lengthMeters(points);
        List<double[]> reduced = GpxParser.simplify(points, properties.getGpxMaxPoints());
        double[] start = reduced.get(0);
        return Optional.of(TrailRoute.builder()
                .courseId(course.courseId())
                .name(course.name())
                .pointCount(reduced.size())
                .lengthM((int) Math.round(length))
                .startLat(start[1])
                .startLng(start[0])
                .payload(GpxParser.toJson(reduced))
                .fetchedAt(now)
                .build());
    }

    private void closeIfQuotaOrKey(KtoPool pool, String resultCode) {
        if (KtoApiClient.RESULT_QUOTA_EXCEEDED.equals(resultCode)
                || KtoApiClient.RESULT_KEY_NOT_REGISTERED.equals(resultCode)) {
            budget.closeForToday(pool, "returnReasonCode=" + resultCode);
        }
    }
}

package com.heattrip.heat_trip_backend.place.service;

import com.heattrip.heat_trip_backend.place.OrsProperties;
import com.heattrip.heat_trip_backend.place.dto.PlaceLoopDto;
import com.heattrip.heat_trip_backend.place.entity.TrailRoute;
import com.heattrip.heat_trip_backend.place.layer.GpxParser;
import com.heattrip.heat_trip_backend.place.layer.LayerPlaceIndex;
import com.heattrip.heat_trip_backend.place.repository.PetPlaceDetailRepository;
import com.heattrip.heat_trip_backend.place.repository.TrailRouteRepository;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 장소에서 출발해 돌아오는 추천 산책 코스 — 이슈 #725 3단계.
 *
 * <h2>한 번 받으면 저장한다 — 캐시가 아니라 저장</h2>
 * <p>공원의 산책길은 바뀌지 않는다. 그래서 (장소, 길이) 하나에 코스 하나를 {@code trail_route} 에
 * {@code loop:{contentId}:{lengthM}} 로 남기고 다음부터는 표에서 읽는다. 레디스 같은 것을 두지
 * 않는 이유: 초 단위로 바뀌는 값이 아니고, 서버가 여러 대여도 표 하나를 같이 본다(#86).
 * ORS 의 하루 한도가 <b>200</b> 이라(실측) 저장 없이는 하루에 코스 수십 개도 못 만든다.
 *
 * <h2>seed 몇 개를 돌려 가장 가까운 것</h2>
 * <p>ORS 의 왕복은 부탁한 길이를 대략만 지킨다. {@link LoopPicker} 가 고르고, 두 배 넘게
 * 어긋나면 안 준다. 시도 하나가 한도 1 이다({@link KtoPool#ORS_LOOP}) — 실패해도 환불하지 않는다,
 * 상대도 실패한 호출을 센다.
 *
 * <h2>못 줄 때는 200 + {@code available=false}</h2>
 * <p>키 없음 · 한도 소진 · 바깥 실패 · 남이 받는 중 — 넷 다 "지금은 없음" 이지 오류가 아니다.
 * 모르는 장소만 404 다(상세와 같은 규칙 — 허용목록 밖은 바깥 호출 0).
 *
 * <h2>출발점은 두 곳에서 찾는다</h2>
 * <p>관광공사 장소는 {@code pet_place_detail}(허용목록)에 있지만, 산책로(두루누비 · 동네 길)와
 * 놀이터는 거기 없다 — 레이어 한 벌({@link LayerPlaceIndex})에만 산다. 처음 판은 허용목록만 봐서
 * 동네 길 1,302곳이 전부 404 였다(2026-09-21, 실기기). 홈 카드의 후보는 대부분 산책로라 추천
 * 코스 줄이 늘 "못 받아요" 였다. 레이어 한 벌도 우리가 실어 보낸 목록이므로 허용목록과 같은 뜻이다
 * — 바깥 호출은 여전히 우리가 아는 장소에만 나간다.
 */
@Service
public class PlaceLoopService {

    public static final int MIN_LENGTH_M = 500;
    public static final int MAX_LENGTH_M = 10_000;
    public static final int STEP_M = 500;
    public static final String COURSE_ID_PREFIX = "loop:";

    /** 도보 예상 시간을 낼 때의 걸음 — 개와 걷는 속도(4.5km/h). ORS 의 값은 저장 칸이 없어 이것으로 통일한다. */
    static final double WALK_METERS_PER_SECOND = 1.25;

    private final TrailRouteRepository routes;
    private final PetPlaceDetailRepository details;
    private final LayerPlaceIndex layers;
    private final OrsRoutingClient ors;
    private final KtoCallBudget budget;
    private final UpstreamGate gate;
    private final OrsProperties properties;
    private final Clock clock;

    public PlaceLoopService(TrailRouteRepository routes,
                            PetPlaceDetailRepository details,
                            LayerPlaceIndex layers,
                            OrsRoutingClient ors,
                            KtoCallBudget budget,
                            UpstreamGate gate,
                            OrsProperties properties,
                            Clock clock) {
        this.routes = routes;
        this.details = details;
        this.layers = layers;
        this.ors = ors;
        this.budget = budget;
        this.gate = gate;
        this.properties = properties;
        this.clock = clock;
    }

    /** 500 ~ 10,000 사이, 500 단위로. 길이마다 코스를 따로 저장하므로 값의 가짓수를 줄인다. */
    public static int normalizeLength(int requestedM) {
        int clamped = Math.max(MIN_LENGTH_M, Math.min(MAX_LENGTH_M, requestedM));
        return (int) (Math.round(clamped / (double) STEP_M) * STEP_M);
    }

    public static String courseIdOf(String contentId, int lengthM) {
        return COURSE_ID_PREFIX + contentId + ":" + lengthM;
    }

    /** 모르는 장소면 빈 값(404). 아는 장소면 늘 값이 있다 — 못 주면 {@code available=false}. */
    public Optional<PlaceLoopDto> loop(String contentId, int requestedLengthM) {
        int lengthM = normalizeLength(requestedLengthM);
        String courseId = courseIdOf(contentId, lengthM);

        Optional<TrailRoute> stored = routes.findById(courseId);
        if (stored.isPresent()) {
            return Optional.of(ready(stored.get(), contentId, lengthM));
        }

        Origin origin = locate(contentId).orElse(null);
        if (origin == null) {
            return Optional.empty();
        }
        if (!ors.isConfigured()) {
            return Optional.of(PlaceLoopDto.unavailable(contentId, lengthM, "nokey"));
        }

        PlaceLoopDto fetched = gate.runIfOwner(courseId, () -> fetchAndStore(origin, contentId, lengthM, courseId));
        if (fetched != null) {
            return Optional.of(fetched);
        }
        // 남이 같은 코스를 받는 중이거나 바깥 자리가 없다 — 그새 끝났으면 표에 있다.
        return Optional.of(routes.findById(courseId)
                .map(row -> ready(row, contentId, lengthM))
                .orElse(PlaceLoopDto.unavailable(contentId, lengthM, "busy")));
    }

    /** 코스의 출발점 — 어디서 알아냈든 좌표와 이름만 남긴다. */
    record Origin(double lat, double lng, String title) { }

    /**
     * 출발점을 찾는다 — 허용목록({@code pet_place_detail})에 먼저, 없으면 레이어 한 벌에서.
     * 둘 다 모르는 id 면 빈 값이고, 그때만 404 다. 레이어 한 벌은 메모리 객체(ETag 가 바뀔 때만
     * 다시 읽음)라 id 하나를 훑는 값은 싸다.
     */
    private Optional<Origin> locate(String contentId) {
        Optional<Origin> known = details.findById(contentId)
                .filter(row -> row.getLat() != null && row.getLng() != null)
                .map(row -> new Origin(row.getLat(), row.getLng(), row.getTitle()));
        if (known.isPresent()) {
            return known;
        }
        return layers.allLayers().stream()
                .filter(p -> contentId.equals(p.contentId()))
                .findFirst()
                .map(p -> new Origin(p.lat(), p.lng(), p.title()));
    }

    private PlaceLoopDto fetchAndStore(Origin place, String contentId, int lengthM, String courseId) {
        List<OrsRoutingClient.Loop> candidates = new ArrayList<>();
        boolean budgetExhausted = false;
        for (int seed = 1; seed <= Math.max(1, properties.getLoopAttempts()); seed++) {
            if (!budget.tryAcquire(KtoPool.ORS_LOOP, 1)) {
                budgetExhausted = true;
                break;
            }
            ors.roundTrip(place.lat(), place.lng(), lengthM, properties.getLoopPoints(), seed)
                    .ifPresent(candidates::add);
        }
        Optional<OrsRoutingClient.Loop> best = LoopPicker.pick(candidates, lengthM);
        if (best.isEmpty()) {
            String reason = candidates.isEmpty() && budgetExhausted ? "budget" : "upstream";
            return PlaceLoopDto.unavailable(contentId, lengthM, reason);
        }
        OrsRoutingClient.Loop loop = best.get();
        double[] start = loop.lngLat().get(0);
        TrailRoute row = routes.save(TrailRoute.builder()
                .courseId(courseId)
                .name(nameOf(place.title(), lengthM))
                .pointCount(loop.lngLat().size())
                .lengthM((int) Math.round(loop.distanceM()))
                .startLat(start[1])
                .startLng(start[0])
                .payload(GpxParser.toJson(loop.lngLat()))
                .fetchedAt(LocalDateTime.now(clock))
                .build());
        return ready(row, contentId, lengthM);
    }

    private static PlaceLoopDto ready(TrailRoute row, String contentId, int lengthM) {
        int distanceM = row.getLengthM();
        int durationS = (int) Math.round(distanceM / WALK_METERS_PER_SECOND);
        return PlaceLoopDto.ready(contentId, lengthM, distanceM, durationS, row.getPointCount(), row.getPayload());
    }

    /** "서울숲 2km 한 바퀴" — 1500 은 "1.5km". */
    static String nameOf(String title, int lengthM) {
        String km = lengthM % 1000 == 0 ? String.valueOf(lengthM / 1000) : String.valueOf(lengthM / 1000.0);
        String place = title == null || title.isBlank() ? "이 장소" : title.strip();
        return place + " " + km + "km 한 바퀴";
    }
}

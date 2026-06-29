package com.heattrip.heat_trip_backend.kakao.service;

import com.heattrip.heat_trip_backend.kakao.client.KakaoLocalClient;
import com.heattrip.heat_trip_backend.kakao.dto.KakaoKeywordResponse;
import com.heattrip.heat_trip_backend.kakao.entity.PlaceKakaoLink;
import com.heattrip.heat_trip_backend.kakao.repository.PlaceKakaoLinkRepository;
import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
public class KakaoLinkBackfillService {

    private final PlaceRepository placeRepository;
    private final PlaceKakaoLinkRepository linkRepository;
    private final KakaoLocalClient kakaoClient;

    @Value("${backfill.kakao.max-distance-m:800}")
    private double maxDistanceM;

    @Value("${backfill.kakao.page-size:200}")
    private int pageSize;

    @Value("${backfill.kakao.delay-ms:250}")
    private long delayMs;

    // ★ 추가: “한 건만” 모드 (비어있지 않으면 그 id 1건만 처리)
    @Value("${backfill.kakao.only-contentid:}")
    private String onlyContentIdStr;

    // ★ 추가: “상위 N건만” 샘플 모드 (0이면 전체)
    @Value("${backfill.kakao.sample-size:0}")
    private int sampleSize;

    public void runOnce() {
        // ❶ only-contentid가 있으면 그 한 건만 처리하고 종료
        Long onlyId = parseLongOrNull(onlyContentIdStr);
        if (onlyId != null) {
            placeRepository.findById(onlyId).ifPresentOrElse(
                this::processSafely,
                () -> log.warn("[Kakao Backfill] place not found: contentid={}", onlyId)
            );
            log.info("[Kakao Backfill] single-id mode done: {}", onlyId);
            return;
        }

        // ❷ sample-size가 > 0이면 앞에서 N건만 처리
        int processed = 0;
        int page = 0;
        while (true) {
            Page<Place> batch = placeRepository.findAll(PageRequest.of(page, pageSize));
            if (batch.isEmpty()) break;

            for (Place p : batch) {
                if (sampleSize > 0 && processed >= sampleSize) {
                    log.info("[Kakao Backfill] sample-size reached: {}", sampleSize);
                    return;
                }
                processSafely(p);
                processed++;
            }

            if (!batch.hasNext()) break;
            page++;
        }
        log.info("[Kakao Backfill] completed. processed={}", processed);
    }

    private void processSafely(Place p) {
        try {
            processOne(p);
            if (delayMs > 0) Thread.sleep(delayMs);
        } catch (Exception e) {
            log.warn("Skip contentid={} title='{}' cause={}", p.getContentid(), p.getTitle(), e.toString());
            // (선택) 실패도 기록해 다음 실행에서 스킵하고 진행상황을 DB에서 확인하고 싶다면 주석 해제
            /*
            if (!linkRepository.existsById(p.getContentid())) {
                linkRepository.save(PlaceKakaoLink.builder()
                        .id(p.getContentid())
                        .title(Optional.ofNullable(p.getTitle()).orElse(""))
                        .placeUrl(null).kakaoMapx(null).kakaoMapy(null)
                        .build());
            }
            */
        }
    }

    private void processOne(Place place) {
        Long id = place.getContentid();

        if (linkRepository.existsById(id)) return;

        String title = normalize(place.getTitle());
        if (title.isBlank()) {
            linkRepository.save(PlaceKakaoLink.builder()
                    .id(id).title("")
                    .placeUrl(null).kakaoMapx(null).kakaoMapy(null)
                    .build());
            return;
        }

        double x = Optional.ofNullable(place.getMapx()).orElse(0.0); // lon
        double y = Optional.ofNullable(place.getMapy()).orElse(0.0); // lat

        KakaoKeywordResponse resp = kakaoClient.searchKeyword(title, x, y).block();
        KakaoKeywordResponse.Document doc = pickBest(resp);

        PlaceKakaoLink.PlaceKakaoLinkBuilder b = PlaceKakaoLink.builder()
                .id(id)
                .title(place.getTitle());

        if (doc != null) {
            Double kx = parseDouble(doc.x);
            Double ky = parseDouble(doc.y);
            if (kx != null && ky != null) {
                double dist = GeoUtils.haversineMeters(x, y, kx, ky);
                if (dist <= maxDistanceM) {
                    b.placeUrl(doc.placeUrl).kakaoMapx(kx).kakaoMapy(ky);
                } else {
                    log.debug("Rejected by distance: {} m > {} (id={}, title={})",
                            Math.round(dist), Math.round(maxDistanceM), id, title);
                }
            }
        }
        linkRepository.save(b.build());
    }

    private static KakaoKeywordResponse.Document pickBest(KakaoKeywordResponse r) {
        if (r == null || r.getDocuments() == null || r.getDocuments().isEmpty()) return null;
        return r.getDocuments().get(0);
    }

    private static Double parseDouble(String v) {
        try { return (v == null) ? null : Double.parseDouble(v); }
        catch (Exception e) { return null; }
    }

    private static String normalize(String s) {
        if (s == null) return "";
        return s.trim().replaceAll("\\s+", " ");
    }

    private static Long parseLongOrNull(String v) {
        try { return (v == null || v.isBlank()) ? null : Long.parseLong(v.trim()); }
        catch (Exception e) { return null; }
    }
}

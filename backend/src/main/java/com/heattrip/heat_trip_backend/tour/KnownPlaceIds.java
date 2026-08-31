package com.heattrip.heat_trip_backend.tour;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/**
 * "이 {@code contentId} 를 우리가 아는가" 에 답한다 — 이슈 #40.
 * <b>{@code tour} 모듈의 공개 표면이다.</b>
 *
 * <h2>왜 이 표면이 필요한가</h2>
 * <p>KTO 프록시의 상세 경로는 <b>허용목록</b>을 먼저 통과해야 한다 — 없으면 무작위
 * {@code contentId} 를 던지는 것만으로 하루 상세 예산(2콜 × 75건)이 사라진다.
 *
 * <p>그런데 앱의 탐색·북마크·컬렉션 화면은 {@code /api/explore/places} 가 준
 * {@code contentId} 로 상세에 들어온다. 그 값들의 출처가 {@code places} 표이고,
 * 그 표는 이 모듈의 것이다.
 *
 * <p>{@code place} 가 {@code PlaceRepository} 를 직접 부르면 <b>모듈 경계 위반</b>이고,
 * 표를 네이티브 쿼리로 훔쳐 읽는 것도 같은 일이다. 그래서 여기가 답한다.
 *
 * <h2>좌표가 없는 행은 모르는 것으로 답한다</h2>
 * <p>지도에 못 찍는 장소를 상세로 열면 앱이 0,0 에 마커를 그린다. 적재가 좌표를 못 받은
 * 행이 실제로 있어서({@code mapx}/{@code mapy} 가 nullable) 여기서 거른다.
 */
@Component
public class KnownPlaceIds {

    private final PlaceRepository places;

    public KnownPlaceIds(PlaceRepository places) {
        this.places = places;
    }

    /**
     * 적재된 장소의 기본 필드. 모르는 id 거나 좌표가 없으면 비어 있다.
     *
     * <p>{@code contentId} 는 문자열로 받는다 — 밖에서는 KTO 가 준 불투명 값이고,
     * 이 표가 그것을 {@code BIGINT} 로 저장한다는 사실은 이 모듈의 사정이다.
     */
    @Transactional(readOnly = true)
    public Optional<PlaceBasics> find(String contentId) {
        long id;
        try {
            id = Long.parseLong(contentId);
        } catch (NumberFormatException e) {
            return Optional.empty();
        }

        return places.findById(id)
                .filter(place -> place.getMapx() != null && place.getMapy() != null)
                .map(KnownPlaceIds::toBasics);
    }

    private static PlaceBasics toBasics(Place place) {
        String image = place.getFirstimage();
        if (image == null || image.isBlank()) {
            image = place.getFirstimage2();
        }
        // 탐색 화면 계열은 addr1 + addr2 를 합쳐 보여 준다(앱의 상세 매퍼가 그렇게 한다).
        String addr = join(place.getAddr1(), place.getAddr2());

        return new PlaceBasics(
                String.valueOf(place.getContentid()),
                place.getTitle() == null ? "" : place.getTitle(),
                addr,
                place.getTel(),
                image,
                place.getMapy(),
                place.getMapx(),
                place.getContenttypeid());
    }

    private static String join(String first, String second) {
        String a = first == null ? "" : first.trim();
        String b = second == null ? "" : second.trim();
        if (a.isEmpty()) {
            return b;
        }
        return b.isEmpty() ? a : a + " " + b;
    }
}

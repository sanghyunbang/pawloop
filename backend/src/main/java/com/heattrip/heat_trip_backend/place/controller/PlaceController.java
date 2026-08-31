package com.heattrip.heat_trip_backend.place.controller;

import com.heattrip.heat_trip_backend.place.dto.PlaceDetailDto;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.place.service.GridCell;
import com.heattrip.heat_trip_backend.place.service.PlaceDetailService;
import com.heattrip.heat_trip_backend.place.service.PlaceQueryService;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

/**
 * 관광공사(KTO) 프록시 — 이슈 #40. 계약은 {@code openapi.yaml} 의 {@code /api/places/**} 다.
 *
 * <h2>이 컨트롤러가 존재하는 이유</h2>
 * <p>앱이 KTO 를 <b>직접</b> 부르고 있었고, 그러려면 서비스키가 앱 바이너리 안에 있어야 했다.
 * {@code --dart-define} 으로 옮겨도 문자열은 그대로 남아서 {@code strings} 한 번이면 나온다.
 * 키는 쿼터·과금이 걸린 자격증명이고, 폐기하려면 <b>앱을 새로 배포</b>해야 하므로 즉시 대응이
 * 불가능하다. 그래서 호출을 서버로 옮긴다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증 없음.</b> 계약이 {@code security: []} 로 선언했다 — 지도는 로그인 전에도
 *       보여야 한다. {@code SecurityConfig} 의 {@code publicMatchers} 에 두 경로를
 *       <b>각각</b> 등재했다({@code /api/places/**} 같은 와일드카드가 아니다 — 아래 참조).</li>
 *   <li><b>rate limit</b> — {@code places} · {@code places-detail} 두 버킷에 등재했다.
 *       표에 없는 경로는 한도가 0 이 아니라 <b>무한</b>이다.</li>
 *   <li><b>호출 예산</b> — IP 한도와 별개로, KTO 로 나가는 호출 자체가 하루 상한을 갖는다
 *       ({@code KtoCallBudget}). 그게 없으면 인증 없는 경로 하나가 우리 쿼터를 태울 수 있다.</li>
 * </ul>
 *
 * <h2>실패해도 200 이다</h2>
 * <p>KTO 가 죽었거나 예산이 소진되면 <b>빈 목록</b>을 준다. 앱은 지금도 실패를 빈 목록으로
 * 다루고 있어서({@code PetPlacesRepository} 가 non-200 을 그렇게 삼킨다) 화면이 깨지지 않는다.
 *
 * <p><b>한계를 그대로 적는다.</b> 그래서 사용자에게는 "한도 초과" 와 "이 주변에 장소가 없음"
 * 이 똑같이 보인다. 운영자는 {@code kto_call_budget} 과 로그로 구분할 수 있고 사용자만 못
 * 한다. 앱이 그 둘을 구분해 보여 주게 하는 것은 별건이다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/places")
public class PlaceController {

    /** 계약의 {@code limit} 기본값. */
    private static final int DEFAULT_LIMIT = 80;

    /** 계약의 {@code limit} 최댓값. 넘겨도 <b>거절하지 않고 자른다</b>. */
    private static final int MAX_LIMIT = 200;

    /** 계약의 {@code radius} 기본값(m). */
    private static final int DEFAULT_RADIUS_M = 8_000;

    private final PlaceQueryService places;
    private final PlaceDetailService details;

    /**
     * 내 주변 반려동반 장소 — 거리순.
     *
     * <h2>{@code radius} 의 상한이 {@link GridCell#GUARANTEED_RADIUS_M} 인 이유</h2>
     * <p>스냅샷은 <b>셀 중심</b>에서 {@link GridCell#FETCH_RADIUS_M} 만큼 받아 둔다.
     * 셀 안의 어떤 점에서도 보장되는 반경은 그것에서 셀 반지름(δ ≈ 1.4km)을 뺀 값이다.
     * 그보다 큰 반경을 받으면 <b>200 으로 조용히 덜 덮인 답</b>을 주게 된다.
     *
     * <p>넘겨도 400 이 아니라 <b>자른다</b> — 계약이 {@code maximum} 으로 선언한 값이고,
     * 앱이 실수로 큰 값을 보냈을 때 지도를 죽이는 것보다 좁혀서 주는 쪽이 낫다.
     * {@code limit} 도 같은 이유로 자른다.
     *
     * <h2>{@code source} 필터를 안 받는다</h2>
     * <p>계약의 {@code category} enum 에 {@code vet}/{@code shop}/{@code trail} 이 있지만
     * 그 셋은 <b>미구현</b>이다(LOCALDATA·두루누비는 좌표변환과 대량 적재가 필요하다).
     * 지금 앱에서도 셋은 더미라 회귀가 아니다. 그 값이 오면 빈 목록이다.
     */
    @GetMapping("/nearby")
    public List<PlaceDto> nearby(@RequestParam("lat") double lat,
                                 @RequestParam("lng") double lng,
                                 @RequestParam(value = "radius", required = false) Integer radius,
                                 @RequestParam(value = "category", required = false) String category,
                                 @RequestParam(value = "limit", required = false) Integer limit) {
        requireFinite(lat, "lat");
        requireFinite(lng, "lng");
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "좌표 범위를 벗어났습니다.");
        }

        // 미구현 레이어는 빈 목록이다. KTO 를 부르지 않는다 — 부르면 예산만 태운다.
        if (category != null && !category.isBlank() && !category.chars().allMatch(Character::isDigit)) {
            return List.of();
        }

        int effectiveRadius = clamp(radius == null ? DEFAULT_RADIUS_M : radius,
                1, GridCell.GUARANTEED_RADIUS_M);
        int effectiveLimit = clamp(limit == null ? DEFAULT_LIMIT : limit, 1, MAX_LIMIT);

        return places.nearby(lat, lng, effectiveRadius,
                category == null || category.isBlank() ? null : category, effectiveLimit);
    }

    /**
     * 장소 상세.
     *
     * <p><b>404 는 아웃바운드 호출 없이</b> 난다. 우리가 목록에 실어 보낸 적도 없고
     * {@code places} 표에도 없는 id 라면 KTO 에 물어볼 이유가 없다 — 물으면 무작위 id 를
     * 던지는 것만으로 하루 상세 예산이 사라진다.
     */
    @GetMapping("/{contentId}")
    public PlaceDetailDto detail(@PathVariable("contentId") String contentId) {
        return details.detail(contentId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "장소를 찾을 수 없습니다."));
    }

    private static void requireFinite(double value, String name) {
        if (Double.isNaN(value) || Double.isInfinite(value)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, name + " 값이 올바르지 않습니다.");
        }
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}

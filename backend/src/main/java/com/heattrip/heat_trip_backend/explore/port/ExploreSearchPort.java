package com.heattrip.heat_trip_backend.explore.port;

import com.heattrip.heat_trip_backend.explore.dto.PageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;
import com.heattrip.heat_trip_backend.explore.dto.search.PlaceSearchCond;

/**
 * 검색 유즈케이스에 대한 추상 포트 (도메인 인터페이스).
 *  - Service는 이 인터페이스에만 의존하고, 실제 구현(JPA, MyBatis, ES 등)은
 *    "어댑터(Adapter)"가 담당한다. ※A-1
 *  - 즉, DB/검색엔진 교체 시 Service/Controller 코드는 수정 없이 유지 가능. ※A-3
 */
public interface ExploreSearchPort {
    PageResponse<PlaceSummaryDto> search(PlaceSearchCond cond);
}

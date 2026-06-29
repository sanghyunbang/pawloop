package com.heattrip.heat_trip_backend.explore.mapper;


import java.sql.Timestamp;
import java.time.LocalDateTime;

import org.mapstruct.BeanMapping;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;
import org.mapstruct.ReportingPolicy;

import com.heattrip.heat_trip_backend.explore.dto.PlaceDetailDto;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;
import com.heattrip.heat_trip_backend.explore.repository.PlaceSummaryProjection;
import com.heattrip.heat_trip_backend.tour.domain.Place;

/**
 * MapStruct 기반 매퍼.
 *
 * - componentModel="spring": 스프링 빈으로 등록되어 @Autowired/@Inject로 주입 가능.
 * - unmappedTargetPolicy=IGNORE: DTO에 없는 필드는 무시(빌드 에러 방지).
 * - 기본적으로 동일한 이름의 필드는 자동 매핑.
 *
 * 여기서는 3가지 변환을 지원:
 *   1) Place(Entity) -> PlaceDetailDto
 *   2) Place(Entity) -> PlaceSummaryDto
 *   3) PlaceSummaryProjection(네이티브 프로젝션, createdtime=Timestamp) -> PlaceSummaryDto(=LocalDateTime)
 */
@Mapper(
    componentModel = "spring",
    unmappedTargetPolicy = ReportingPolicy.IGNORE,
    uses = JsonListMapper.class               // [0825] 추가: 문자열 JSON → List 변환기 사용
)
public interface PlaceMapper {

    /* -------------------------------------------------------------
     * 1) Entity -> 상세 DTO
     *  - 필드명이 대부분 동일하므로 추가 @Mapping 없이 자동 매핑됩니다.
     * ------------------------------------------------------------- */
    PlaceDetailDto toDetail(Place place);

    /* -------------------------------------------------------------
     * 2) Entity -> 요약 DTO
     *  - 목록 화면용. 동일 이름 자동 매핑.
     * ------------------------------------------------------------- */
    PlaceSummaryDto toSummary(Place place);

    /* -------------------------------------------------------------
     * 3) Projection -> 요약 DTO
     *  - 네이티브 쿼리 결과(PlaceSummaryProjection)의 createdtime은 Timestamp.
     *  - DTO의 createdtime(LocalDateTime)으로 변환해 주어야 하므로
     *    @Named 메서드(tsToLdt)를 만들어 qualifiedByName로 연결합니다.
     * ------------------------------------------------------------- */

    // 요약 (여기에 매핑 보강)
    @Mapping(source = "createdtime",  target = "createdtime",  qualifiedByName = "tsToLdt")
    @Mapping(source = "hashtagsJson", target = "hashtags",     qualifiedByName = "jsonToList")     // 추가
    @Mapping(source = "simpleTagsJson", target = "simpleTags", qualifiedByName = "jsonToList")     // 추가
    // cat3 / cat3Name / shortDesc1 / shortDesc2 / addr1 / addr2 / firstimage2 등은
    // 이름이 같으므로 자동 매핑됩니다.
    PlaceSummaryDto toSummary(PlaceSummaryProjection p);

    /* -------------------------------------------------------------
     * 공용 변환 유틸 (@Named)
     *  - MapStruct가 호출할 수 있도록 default/static 메서드로 제공.
     * ------------------------------------------------------------- */
    @Named("tsToLdt")
    public static LocalDateTime tsToLdt(Timestamp ts) {
        return ts == null ? null : ts.toLocalDateTime();
    }

    /* -------------------------------------------------------------
     * 참고) 필요시 null-handling, trimming, formatting 등을
     *  BeanMapping이나 @Mapping(expression="java(...)")로 확장할 수 있습니다.
     * ------------------------------------------------------------- */
    @BeanMapping(ignoreByDefault = false)
    default PlaceSummaryDto safeProjectionToSummary(PlaceSummaryProjection p) {
        // 위 @Mapping 메서드와 동일하지만, 추가 후처리가 필요할 때 사용할 수 있는 예비 메서드.
        return toSummary(p);
    }
}
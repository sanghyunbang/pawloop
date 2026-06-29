package com.heattrip.heat_trip_backend.explore.repository;


import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;

import java.util.List;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 읽기 전용 조회(요약 리스트)용 Repository.
 * - Spring Data JPA의 @Query(JPQL) + "DTO 생성자 표현식(NEW ...)"을 사용하여
 *   엔티티를 바로 DTO로 투영해 반환합니다.
 * - {@code Page<T>} 반환이므로 Spring Data가 count 쿼리도 함께 실행해 총 개수를 계산합니다.
 *
 * 주의(중요):
 * 1) 아래 @Query는 "JPQL"입니다(네이티브 SQL 아님). 따라서 FROM 절의 대상은 "테이블"이 아니라 "엔티티 클래스(Place)"여야 하고,
 *    SELECT 절의 필드도 엔티티 필드명(p.title 등)을 사용해야 합니다.
 * 2) NEW com....PlaceSummaryDto(...) 구문은 "DTO 생성자 표현식"입니다.
 *    → PlaceSummaryDto 에 public 생성자가 정확히 같은 파라미터 순서/타입으로 존재해야 합니다.
 * 3) Pageable의 정렬(Sort)은 @Query 사용 시 자동 삽입되지 않을 수 있습니다.
 *    - 정렬이 필수라면 JPQL에 직접 ORDER BY를 넣거나,
 *      SpEL을 이용한 정렬 삽입(예: ORDER BY ?#{#pageable}) 패턴을 고려하세요.
 *    - 지금 코드는 정렬을 JPQL에 명시하지 않으므로, 컨트롤러/서비스에서 Pageable의 sort를 넘겨도
 *      DB 차원에서 보장된 순서가 아닐 수 있습니다(벤더/버전에 따라 다름).
 * 4) WHERE 절의 "(:param IS NULL OR col = :param)" 패턴은 단일 쿼리로 동적 필터링을 처리할 수 있는 장점이 있지만,
 *    인덱스 활용이 떨어질 수 있습니다(선택도가 낮으면 풀스캔 위험). QueryDSL/스펙으로 "조건이 있을 때만 추가"하는 방식도 고려.
 */
public interface ExplorePlaceRepository extends JpaRepository<Place, Long>{

    @Query("""
    SELECT NEW com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto(
        p.contentid, p.title, p.firstimage, p.areacode, p.sigungucode, p.createdtime
    )
    from Place p
    where (:areacode is null or p.areacode = :areacode)
      and (:sigungucode is null or p.sigungucode = :sigungucode)
      and (:cat1 is null or p.cat1 = :cat1)
      and (:cat2 is null or p.cat2 = :cat2)
      and (:cat3List is null or p.cat3 in :cat3List) 
      order by p.createdtime desc, p.contentid desc

        """)
    /**
     * 요약 리스트 조회(JPQL → DTO 직생성, Offset 페이지네이션).
     *
     * @param areacode     지역 코드(옵션). null이면 조건 무시.
     * @param sigungucode  시군구 코드(옵션). null이면 조건 무시.
     * @param cat1         카테고리1(옵션). null이면 조건 무시.
     * @param cat2         카테고리2(옵션). null이면 조건 무시.
     * @param cat3         카테고리3(옵션). null이면 조건 무시.
     * @param pageable     Page/Size(+Sort) 정보를 담은 Pageable.
     *                     - JPQL @Query에서 정렬이 자동 주입되지 않을 수 있으므로,
     *                       결과 순서가 중요하면 JPQL에 ORDER BY를 명시하는 것을 권장.
     *                     - Page 반환이므로 COUNT 쿼리도 함께 수행되어 totalElements가 계산됩니다.
     *                       대용량에서 count 비용이 크면 Slice 반환으로 바꾸는 것도 방법입니다.
     *
     * @return {@code Page<PlaceSummaryDto>} 페이징된 요약 DTO 목록 + 페이지 메타 정보
     *
     * 동작 개요:
     * - 엔티티 Place를 FROM으로 조회하고, 필요한 필드만 뽑아 NEW PlaceSummaryDto(...)로 즉시 매핑.
     * - WHERE 절은 각 파라미터가 null일 때 해당 조건을 건너뛰는 형태로 동적 필터링을 수행.
     * - Pageable로 setFirstResult/setMaxResults가 적용되어 OFFSET 기반 페이지네이션이 수행됩니다.
     */
    Page<PlaceSummaryDto> findSummaries(
        @Param("areacode") Integer areacode,
        @Param("sigungucode") Integer sigungucode,
        @Param("cat1") String cat1,
        @Param("cat2") String cat2,
        @Param("cat3List") List<String> cat3List,
        Pageable pageable);
    
}

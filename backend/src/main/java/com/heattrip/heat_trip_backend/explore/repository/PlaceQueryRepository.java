package com.heattrip.heat_trip_backend.explore.repository;

import java.sql.Timestamp;
import java.util.List;

import com.heattrip.heat_trip_backend.tour.domain.Place;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface PlaceQueryRepository extends JpaRepository<Place, Long> {

    /**
     * 커서 기반(Keyset) 페이지네이션 + 선택적 필터(지역/카테고리)를 네이티브 SQL로 수행하는 메서드.
     * 반환 타입은 "인터페이스 기반 프로젝션(PlaceSummaryProjection)"이며,
     * 아래 SELECT 절의 컬럼 별칭(alias)과 프로젝션의 getter 이름이 일치해야 매핑됩니다.
     *
     * [!] 중요한 포인트
     * - nativeQuery = true 이므로 문법은 DB(SQL) 기준입니다(JPQL 아님).
     * - LIMIT는 명시하지 않고, 메서드 파라미터의 Pageable이 내부적으로 setMaxResults 로 제한을 겁니다.
     * - 커서 값(afterCreated, afterId)을 이용하여 "이전 페이지 마지막 행" 이후의 다음 묶음을 안정적으로 이어받습니다.
     * - createdtime 동일 시 contentid 보조 정렬키로 중복/누락 없이 순서를 고정합니다.
     *
     * ⚠️ 타입 주의
     * - p.createdtime 이 DATETIME/TIMESTAMP 컬럼이어야 java.sql.Timestamp 파라미터 비교가 자연스럽습니다.
     *   (만약 'YYYYMMDDHHmmss' 정수/문자라면 파라미터와 비교 로직을 그에 맞춰야 합니다.)
     */
    @Query(value = """
      SELECT
          p.contentid   AS contentid,    -- 프로젝션: getContentid()
          p.title       AS title,        -- 프로젝션: getTitle()
          p.firstimage  AS firstimage,   -- 프로젝션: getFirstimage()
          -- p.areacode    AS areacode,     -- 프로젝션: getAreacode() (주석 처리 [0822])
          -- p.sigungucode AS sigungucode,  -- 프로젝션: getSigungucode() (주석 처리 [0822])
          p.createdtime AS createdtime,   -- 프로젝션: getCreatedtime() 
          p.addr1 AS addr1,          -- 프로젝션: getAddr1() (추가 [0822])
          p.addr2 AS addr2,          -- 프로젝션: getAddr2() (추가 [0822])
          p.firstimage2 AS firstimage2, -- 프로젝션: getFirstimage2() (추가 [0822])
          p.contenttypeid AS contentTypeId, -- 프로젝션: getContentTypeId() (추가 [0822])
          
          /* 스냅샷 추가 [0825]*/
          s.cat3         AS cat3,            -- getCat3()
          s.cat3name    AS cat3Name,        -- getCat3Name()
          s.short_desc1  AS shortDesc1,      -- getShortDesc1()
          s.short_desc2  AS shortDesc2,      -- getShortDesc2()
          -- [! 주의 ] ▼ JSON 컬럼은 “반드시 문자열로 캐스팅”해서 별칭 부여
          CAST(s.hashtags    AS CHAR) AS hashtagsJson,    -- ← 게터: getHashtagsJson()
          CAST(s.simple_tags AS CHAR) AS simpleTagsJson   -- ← 게터: getSimpleTagsJson()   
          FROM places p
          JOIN place_trait_snapshots s
            ON p.cat3 = s.cat3
      WHERE (:areacode    IS NULL OR p.areacode    = :areacode)         -- 지역 코드 필터(선택): null이면 건너뜀
        AND (:sigungucode IS NULL OR p.sigungucode = :sigungucode)       -- 시군구 코드 필터(선택)
        AND (:cat1 IS NULL OR p.cat1 = :cat1)                            -- 카테고리1 필터(선택)
        AND (:cat2 IS NULL OR p.cat2 = :cat2)                            -- 카테고리2 필터(선택)
        AND (:cat3Csv IS NULL OR FIND_IN_SET(p.cat3, :cat3Csv) > 0)                        -- 카테고리3 필터(선택)
        AND (
          :afterCreated IS NULL                                           -- 첫 페이지: 커서가 없으면 최신부터 시작
          OR p.createdtime < :afterCreated                                -- 이전 페이지 마지막 createdtime 보다 "더 과거(작은)" 행
          OR (p.createdtime = :afterCreated AND p.contentid < :afterId)   -- 동시간대의 경우 contentid 로 안정적인 이어받기
        )
        -- [0825] firstimage 가 null/빈문자/공백이면 제외
        AND NULLIF(TRIM(p.firstimage), '') IS NOT NULL

      ORDER BY p.createdtime DESC, p.contentid DESC                       /*최신순 정렬 + 보조키로 안정화*/
      """,
      nativeQuery = true)
    List<PlaceSummaryProjection> findNextByCursor(
        @Param("areacode") Integer areacode,          // 선택적 지역 필터(Null 허용)
        @Param("sigungucode") Integer sigungucode,    // 선택적 시군구 필터(Null 허용)
        @Param("cat1") String cat1,                   // 선택적 카테고리1
        @Param("cat2") String cat2,                   // 선택적 카테고리2
        @Param("cat3Csv") String cat3Csv,                   // 선택적 카테고리3
        @Param("afterCreated") Timestamp afterCreated,// 커서: 이전 페이지 마지막 행의 createdtime (첫 페이지면 null)
        @Param("afterId") Long afterId,               // 커서: 이전 페이지 마지막 행의 contentid (동시간대 정렬 안정용)
        Pageable pageable                             // 페이지 크기 제한 담당(보통 PageRequest.of(0, size)로 offset=0 권장)
    );
}

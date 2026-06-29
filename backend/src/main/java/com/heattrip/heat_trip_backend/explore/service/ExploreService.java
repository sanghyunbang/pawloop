package com.heattrip.heat_trip_backend.explore.service;

import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.NoSuchElementException;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.heattrip.heat_trip_backend.explore.dto.CursorPageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PageResponse;
import com.heattrip.heat_trip_backend.explore.dto.PlaceDetailDto;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSearchCond;
import com.heattrip.heat_trip_backend.explore.dto.PlaceSummaryDto;
import com.heattrip.heat_trip_backend.explore.mapper.PlaceMapper;               // ← MapStruct 매퍼 주입 (Entity/Projection → DTO 변환 담당)
import com.heattrip.heat_trip_backend.explore.repository.PlaceQueryRepository; // ← 네이티브 + 커서(Keyset) 페이지네이션용 Repository
import com.heattrip.heat_trip_backend.explore.repository.ExplorePlaceRepository;      // ← JPQL + 오프셋(페이지/사이즈) 페이지네이션용 Repository
import com.heattrip.heat_trip_backend.explore.repository.PlaceSummaryProjection;
import com.heattrip.heat_trip_backend.tour.domain.Place;


import com.heattrip.heat_trip_backend.explore.port.ExploreSearchPort;


/**
 * Explore 도메인의 조회용 비즈니스 로직 계층.
 *
 * 책임(Responsibilities)
 * - 트랜잭션 경계 설정(@Transactional(readOnly = true)).
 * - 입력 검증(간단한 size 상한 등), 페이지네이션 전략(Offset / Cursor) 선택 및 실행.
 * - 엔티티/프로젝션을 API 응답 DTO로 매핑(MapStruct).
 *
 * 설계 요점(Why)
 * - Repository는 "데이터 접근"까지 담당, 이 Service는 "규칙/흐름/조합"을 담당.
 * - 오프셋 페이지네이션(list)과 커서 페이지네이션(scroll)을 분리 제공:
 *   · 오프셋: 총 개수 집계/임의 페이지 접근이 쉬움(대신 대용량에서는 느릴 수 있음).
 *   · 커서  : 무한 스크롤/다음 페이지만 빠르게(대용량에서 안정적, 중간 삽입/삭제에 강함).
 */
@Service
@Transactional(readOnly = true) // ← 읽기 전용 트랜잭션: JPA 변경 감지 비활성 최적화(일부 DB 힌트/캐시 유리)
public class ExploreService {

    private final ExplorePlaceRepository repo;            // ← Offset 페이지네이션용(JPQL로 DTO 생성 반환)
    private final PlaceQueryRepository cursorRepo; // ← Cursor 페이지네이션용(네이티브 + Projection)
    private final PlaceMapper mapper;              // ← MapStruct 매퍼(컴파일타임 생성 코드로 고성능 매핑)
    private final ExploreSearchPort searchPort;     // ★ 신규: 포트/어댑터

    public ExploreService(
        ExplorePlaceRepository repo,
        PlaceQueryRepository cursorRepo,
        PlaceMapper mapper,
        ExploreSearchPort searchPort // ★ 추가 주입

    ) {
        this.repo = repo;
        this.cursorRepo = cursorRepo;
        this.mapper = mapper;
        this.searchPort = searchPort; // ★ 저장

    }

    /** 
     * 상세 조회
     * - 책임: 단건 엔티티 로딩 → 상세 DTO로 매핑.
     * - 예외: 존재하지 않는 경우 NoSuchElementException 발생(컨트롤러에서 404로 매핑 권장).
     */
    public PlaceDetailDto get(Long id) {
        Place p = repo.findById(id).orElseThrow(() -> new NoSuchElementException("Place not found: " + id));
        // 엔티티 → DTO 변환(필드명/타입 변환, 필요시 추가 가공은 MapStruct 매퍼에서 정의)
        return mapper.toDetail(p);
    }

    /**
     * Offset 페이지네이션(전통적 page/size 방식).
     *
     * 동작
     * - page, size 기반으로 PageRequest 생성.
     * - 정렬은 createdtime DESC, contentid DESC (최신순 + 보조 키로 안정화).
     * - repo.findSummaries(...) 가 JPQL에서 DTO를 직접 생성하므로 추가 매핑 불필요.
     *
     * 장단점
     * - 장점: 임의 페이지 점프, 총 개수(totalElements) 제공 쉬움.
     * - 단점: page가 커질수록 OFFSET 스캔 비용 증가(대용량 비추천).
     */

    // Csv -> 리스트화
    private List<String> parseCsvToList(String csv){
        if (csv == null || csv.isBlank()) return null;
        return java.util.Arrays.stream(csv.split(","))
            .map(String::trim)
            .filter(s-> !s.isEmpty())
            .distinct()
            .toList();
    }
    public PageResponse<PlaceSummaryDto> list(PlaceSearchCond c, int page, int size) {
        int safeSize = Math.max(1, Math.min(size, 100)); // ← 안전장치: 최소 1, 최대 100(과도한 page size 방지)
        var sort = Sort.by(Sort.Order.desc("createdtime"), Sort.Order.desc("contentid")); // ← 안정 정렬(동시간대 contentid로 확정)
        var pageable = PageRequest.of(Math.max(page, 0), safeSize, sort);                  // ← page 하한 0 보정

        List<String> cat3List = parseCsvToList(c.getCat3());

        // JPQL에서 new PlaceSummaryDto(...) 로 직접 생성해서 반환 → 여기서 별도 매핑 없음
        Page<PlaceSummaryDto> p = repo.findSummaries(
            c.getAreacode(), c.getSigungucode(),
            c.getCat1(), c.getCat2(), cat3List,
            pageable
        );

        // Page → API 응답 래퍼로 재구성(페이지 메타 정보 포함)
        return new PageResponse<>(p.getContent(), p.getNumber(), p.getSize(), p.getTotalElements(), p.isLast());
    }

    /**
     * Cursor(무한 스크롤) 페이지네이션.
     *
     * 핵심 개념(Keyset Pagination)
     * - 정렬 키 쌍(createdtime DESC, contentid DESC)을 "커서"로 인코딩하여,
     *   "이 커서보다 뒤(=더 과거)"의 레코드를 다음 페이지로 가져옴.
     * - OFFSET 미사용 → 대용량에서도 성능/안정성 우수. 중간 삽입/삭제에도 누락/중복 최소화.
     *
     * 커서 포맷
     * - cursor = Base64URL("epochMillis:contentid")
     *   · epochMillis: createdtime을 UTC 기준 epoch milli로 변환했다는 가정(아래 nextCursor 생성 로직 참고).
     *   · contentid  : 동일 timestamp에서의 안정 보조 키.
     *
     * 주의
     * - 커서가 변조/구버전일 수 있으므로 실제 운영에서는 try-catch로 파싱 실패 시 첫 페이지 처리 권장(여긴 "주석만" 요구라 코드 변경 없음).
     * - DB의 createdtime 타임존/타입과 앱의 변환 기준(UTC/KST)이 다르면 커서 불일치가 생길 수 있음(아래 ⑥ 설명 참고).
     */
    public CursorPageResponse<PlaceSummaryDto> scroll(PlaceSearchCond c, String cursor, int size) {
        int safeSize = Math.max(1, Math.min(size, 100));
        int sizePlusOne = safeSize + 1;

        // ① 커서 디코딩 (방어적으로)
        java.sql.Timestamp afterCreated = null;
        Long afterId = null;
        if (cursor != null && !cursor.isBlank()
                && !"null".equalsIgnoreCase(cursor)
                && !"undefined".equalsIgnoreCase(cursor)) {
            try {
                String raw = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
                String[] parts = raw.split(":");
                long millis = Long.parseLong(parts[0]);
                afterCreated = new java.sql.Timestamp(millis);
                afterId = Long.parseLong(parts[1]);
            } catch (Exception ignore) {
                // 커서가 이상하면 그냥 첫 페이지 취급
                afterCreated = null;
                afterId = null;
            }
        }

        var pageable = PageRequest.of(0, sizePlusOne);

        // ② 쿼리 호출
        List<PlaceSummaryProjection> rows = cursorRepo.findNextByCursor(
            c.getAreacode(), c.getSigungucode(), c.getCat1(), c.getCat2(), c.getCat3(),
            afterCreated, afterId, pageable
        );

        boolean hasNext = rows.size() > safeSize;

        // ③ DTO 매핑
        var slice = rows.stream().limit(safeSize).toList();
        List<PlaceSummaryDto> items = slice.stream()
                .map(mapper::toSummary)
                .toList();

        // ④ nextCursor 만들기(프로젝션에서 직접 꺼내 NULL 방지)
        String nextCursor = null;
        if (hasNext && !slice.isEmpty()) {
            java.sql.Timestamp lastTs = null;
            Long lastId = null;
            for (int i = slice.size() - 1; i >= 0; i--) {
                var r = slice.get(i);
                if (r.getCreatedtime() != null) {
                    lastTs = r.getCreatedtime();
                    lastId = r.getContentid();
                    break;
                }
            }
            if (lastTs != null && lastId != null) {
                long millis = lastTs.getTime();
                nextCursor = Base64.getUrlEncoder()
                        .encodeToString((millis + ":" + lastId).getBytes(StandardCharsets.UTF_8));
            }
        }

        return new CursorPageResponse<>(items, nextCursor, hasNext);
    }
    
        /**
     * 신규: 저결합 포트/어댑터 기반 "키워드/카테고리 검색"
     * - 기존 메서드들과 충돌 피하기 위해 이름을 searchAdvanced 로 둡니다.
     * - DTO 충돌을 피하려고 매개변수는 'search' 하위 패키지의 PlaceSearchCond 를 완전수형으로 사용. ※S-1
     */
    public PageResponse<PlaceSummaryDto> searchAdvanced(
        com.heattrip.heat_trip_backend.explore.dto.search.PlaceSearchCond cond
    ) {
        // 어댑터(JPA Criteria)로 위임 → PageResponse<PlaceSummaryDto> 반환
        return searchPort.search(cond);
    }
}

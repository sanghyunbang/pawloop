package com.heattrip.heat_trip_backend.explore.dto;

import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * Offset 페이지네이션(전통적 page/size) 응답 DTO.
 *
 * 목적(What)
 * - 클라이언트가 특정 page, size로 요청했을 때, 그 결과 목록과 페이지 메타데이터를 함께 전달.
 *
 * 특징(How/Why)
 * - Lombok @Getter + @AllArgsConstructor 만 사용 → 불변(Setter 없음) 응답 객체.
 * - 직렬화는 Jackson이 getter를 통해 수행.
 * - 역직렬화(요청 바디→객체)는 보통 필요 없으므로 기본 생성자 없음(@NoArgsConstructor 불필요).
 *
 * 주의
 * - totalElements는 DB에서 COUNT 쿼리를 추가 수행해야 하므로 대용량에서 비용이 큼.
 *   무한 스크롤 등에서는 CursorPageResponse(커서 페이징) 사용을 고려.
 *
 * 예시(JSON)
 * {
 *   "content": [ { ...DTO... }, { ...DTO... } ],
 *   "page": 2,
 *   "size": 20,
 *   "totalElements": 12345,
 *   "last": false
 * }
 */
@Getter
@AllArgsConstructor
public class PageResponse<T> {

    public PageResponse(List<PlaceSummaryDto> content2, long total, int page2, int size2) {
        //TODO Auto-generated constructor stub
    }

    // 현재 페이지에 포함된 실제 데이터(요약/상세 DTO 등).
    // - 제네릭 T로 재사용성을 유지.
    private List<T> content;

    // 0 기반 페이지 인덱스(예: 첫 페이지면 0).
    private int page;

    // 요청/서버가 결정한 페이지 크기(한 페이지에 들어가는 항목 수).
    private int size;

    // 전체 데이터 개수. Page<T>를 사용할 때 Spring Data가 COUNT 쿼리로 계산.
    // - 비용이 크므로 트래픽 많은 엔드포인트는 주의.
    private long totalElements;

    // 현재 페이지가 마지막 페이지인지 여부.
    // - Page.isLast()를 그대로 전달.
    private boolean last;
}

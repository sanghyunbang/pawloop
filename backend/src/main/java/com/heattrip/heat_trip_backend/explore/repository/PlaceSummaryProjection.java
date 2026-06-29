package com.heattrip.heat_trip_backend.explore.repository;

import java.sql.Timestamp;

/**
 * 인터페이스 기반 Projection.
 *
 * 목적
 * - 네이티브/JPQL 쿼리 결과에서 "필요한 필드만" 가볍게 가져오기 위한 읽기 전용 뷰.
 * - 엔티티 전체를 영속성 컨텍스트에 올리지 않아도 되므로 메모리·성능상 유리.
 *
 * 매핑 규칙(중요)
 * - 네이티브 쿼리를 사용할 경우, SELECT 절의 컬럼에 반드시 "alias" 를 주고
 *   그 alias 가 아래 getter 이름(접두어 get 제거한 프로퍼티명)과 일치해야 함.
 *   예) SELECT p.contentid AS contentid → getContentid()
 * - JPQL이라면 엔티티 필드명과 프로퍼티명이 매핑 기준이 됨.
 *
 * 주의 사항
 * - Projection은 "조회 전용"으로만 사용(컨트롤러에 직접 반환하지 말고, 서비스에서 DTO로 변환 권장).
 * - null 가능성이 있는 컬럼은 프리미티브 타입(int, long 등) 대신 래퍼 타입(Integer, Long)을 사용(이미 잘 사용 중).
 * - Timestamp 타입은 DB 드라이버/콜럼 타입에 따라 LocalDateTime으로도 받을 수 있음.
 *   외부 응답 DTO에서는 java.time 계열 사용 권장(타임존/직렬화 안전).
 */
public interface PlaceSummaryProjection {

  Long getContentid();      // SELECT ... AS contentid  ← 커서 보조 키이자 식별자. null 가능 시 Long 유지.

  String getTitle();        // SELECT ... AS title      ← 목록 카드/요약 표시용 제목.

  String getFirstimage();   // SELECT ... AS firstimage ← 대표 이미지 URL(없을 수 있으므로 String).

  String getAddr1();        // SELECT ... AS addr1     ← 주소1(시도/구군 등) 표시용. null 가능.

  String getAddr2();        // SELECT ... AS addr2     ← 주소2(동/읍면 등) 표시용. null 가능.

  String getFirstimage2();  // SELECT ... AS firstimage2 ← 플러터와 통일된 추가 이미지 URL(없을 수 있으므로 String).

  // Integer getAreacode();    // SELECT ... AS areacode   ← 지역 필터/표시용. null 허용으로 Integer 사용.

  // Integer getSigungucode(); // SELECT ... AS sigungucode← 시군구 코드. 마찬가지로 null 허용.

  Timestamp getCreatedtime(); // SELECT ... AS createdtime ← 정렬/커서 기준 키.
                              //  - 네이티브에서 DATETIME/TIMESTAMP 컬럼이면 Timestamp로 수신.
                              //  - 서비스/매퍼에서 LocalDateTime으로 변환해 DTO에 담는 것을 권장.

  Integer getContentTypeId(); // SELECT ... AS contentTypeId ← 콘텐츠 타입 ID. null 가능 시 Integer 유지.

  // ▼ 스냅샷 필드들
  String getCat3();
  String getCat3Name();
  String getShortDesc1();
  String getShortDesc2();
  String getHashtagsJson();   // JSON 문자열로 받음
  String getSimpleTagsJson(); // JSON 문자열로 받음
                            
}

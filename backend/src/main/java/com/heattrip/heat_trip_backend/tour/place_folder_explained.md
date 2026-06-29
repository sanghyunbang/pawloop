com.heattrip.heat_trip_backend
 ├─ config
 ├─ OAuth
 ├─ schedules
 ├─ user
 └─ tour
     ├─ domain
     │   └─ Place.java                // JPA Entity
     ├─ dto
     │   └─ PlaceItemDto.java         // XML -> DTO
     ├─ mapper
     │   └─ PlaceMapper.java        // ← 여기에 toEntity/toDto
     ├─ repository
     │   └─ PlaceRepository.java      // Spring Data JPA
     ├─ service
     │   ├─ PlaceService.java         // 비즈 로직, 배치 저장
     │   └─ PlaceImportService.java   // XML 파싱/매핑 + 저장 오케스트레이션
     ├─ util
     │   └─ XmlParser.java            // XML -> DTO 리스트
     └─ web
         └─ PlaceImportController.java // (선택) 수동 트리거용

DB 준비하기 

대량 조회·중복 방지·정렬을 위해 인덱스를 준비

```
ALTER TABLE places
  ADD PRIMARY KEY (contentid),
  ADD INDEX idx_places_areacode_sigungucode (areacode, sigungucode),
  ADD INDEX idx_places_cat (cat1, cat2, cat3),
  ADD INDEX idx_places_type (contenttypeid);
```

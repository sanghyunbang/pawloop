package com.heattrip.heat_trip_backend.tour.mapper;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;

/***
 *  
매퍼가 양방향(Entity ↔ DTO)을 지원하는 이유

1. 저장할 때 (DTO → Entity)

외부 API나 XML, JSON 같은 입력 데이터는 보통 Entity가 아니라 DTO로 먼저 받습니다.
DB에 넣으려면 DTO를 Entity로 변환해야 합니다.

예: PlaceItemDto → Place → placeRepository.saveAll(...)

2. 조회할 때 (Entity → DTO)

DB에서 Entity를 꺼내면 JPA 엔티티 객체입니다.
하지만 API 응답(JSON)으로 내보낼 때는 직접 Entity를 노출하면 안 되는 경우가 많습니다.
 - 지연로딩(Lazy Loading) 때문에 직렬화 문제 발생
 - 보안상 민감 정보 노출 가능성
 - 응답에 필요한 필드만 보내고 싶을 수 있음

그래서 Entity를 DTO로 변환해서 반환합니다.

예: Place → PlaceItemDto → JSON 응답
 */
public class PlaceMapper {
    
    // toEntiy -> DTO를 DB에 저장할 수 있는 Entity로 변환
    public static Place toEntity(PlaceItemDto dto){
        if (dto == null) return null;
        return Place.builder()
            .contentid(dto.getContentid())
            .title(dto.getTitle())
            .addr1(dto.getAddr1())
            .addr2(dto.getAddr2())
            .zipcode(dto.getZipcode())
            .mapx(dto.getMapx())
            .mapy(dto.getMapy())
            .firstimage(dto.getFirstimage())
            .firstimage2(dto.getFirstimage2())
            .cat1(dto.getCat1())
            .cat2(dto.getCat2())
            .cat3(dto.getCat3())
            .areacode(dto.getAreacode())
            .sigungucode(dto.getSigungucode())
            .lDongRegnCd(dto.getLDongRegnCd())
            .lDongSignguCd(dto.getLDongSignguCd())
            .tel(dto.getTel())
            .contenttypeid(dto.getContenttypeid())
            .createdtime(dto.getCreatedtime())
            .modifiedtime(dto.getModifiedtime())
            .mlevel(dto.getMlevel())
            .build();
    }

    // toDto -> DB에서 꺼낸 Entity를 API 응답용 DTO로 변환
    public static PlaceItemDto toDto(Place entity){
        if (entity == null) return null;
        return PlaceItemDto.builder()
            .contentid(entity.getContentid())
            .title(entity.getTitle())
            .addr1(entity.getAddr1())
            .addr2(entity.getAddr2())
            .zipcode(entity.getZipcode())
            .mapx(entity.getMapx())
            .mapy(entity.getMapy())
            .firstimage(entity.getFirstimage())
            .firstimage2(entity.getFirstimage2())
            .cat1(entity.getCat1())
            .cat2(entity.getCat2())
            .cat3(entity.getCat3())
            .areacode(entity.getAreacode())
            .sigungucode(entity.getSigungucode())
            .lDongRegnCd(entity.getLDongRegnCd())
            .lDongSignguCd(entity.getLDongSignguCd())
            .tel(entity.getTel())
            .contenttypeid(entity.getContenttypeid())
            .createdtime(entity.getCreatedtime())
            .modifiedtime(entity.getModifiedtime())
            .mlevel(entity.getMlevel())
            .build();     
    }
}

package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.entity.PetPlaceDetailRow;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;

/** 장소 상세 캐시 — 이슈 #40. */
public interface PetPlaceDetailRepository extends JpaRepository<PetPlaceDetailRow, String> {

    /**
     * 목록에 실어 보낸 장소들을 <b>허용목록에 등재</b>한다.
     *
     * <p>이미 있으면 <b>기본 필드만</b> 덮어쓴다. 스냅샷이 더 최신이기 때문이다.
     * {@code overview}·{@code petInfo}·조회 시각은 <b>안 건드린다</b> — 이미 받아 둔 상세를
     * 지우면 그것을 다시 받는 데 예산이 든다.
     *
     * <p>한 번에 최대 {@code numOfRows} 개(기본 1,000)라 배치 하나로 끝난다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            insert into pet_place_detail
                   (content_id, title, addr, tel, image, lat, lng, content_type_id)
            values (:contentId, :title, :addr, :tel, :image, :lat, :lng, :contentTypeId)
            on duplicate key update
                   title = values(title),
                   addr = values(addr),
                   tel = values(tel),
                   image = values(image),
                   lat = values(lat),
                   lng = values(lng),
                   content_type_id = values(content_type_id)
            """, nativeQuery = true)
    void registerFromSnapshot(@Param("contentId") String contentId,
                              @Param("title") String title,
                              @Param("addr") String addr,
                              @Param("tel") String tel,
                              @Param("image") String image,
                              @Param("lat") Double lat,
                              @Param("lng") Double lng,
                              @Param("contentTypeId") String contentTypeId);

    /** 이 id 들 중 우리가 아는 것. 허용목록 판정에 쓴다. */
    @Query("select r.contentId from PetPlaceDetailRow r where r.contentId in :ids")
    java.util.List<String> findKnownIds(@Param("ids") Collection<String> ids);
}

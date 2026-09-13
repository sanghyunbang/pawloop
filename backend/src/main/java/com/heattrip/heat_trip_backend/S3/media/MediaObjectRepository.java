package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Collection;
import java.util.List;

public interface MediaObjectRepository extends JpaRepository<MediaObject, Long> {
    boolean existsByObjectKey(String objectKey);
    /** 컨트롤러/서비스에서 사용 */
    List<MediaObject> findByRefTypeAndRefId(String refType, String refId);
    List<MediaObject> findByOwnerIdAndCategory(String ownerId, UploadCategory category);

    /** 한 글에 붙은 것. {@code id} 순 = 올린 순이다 — 앱이 순서대로 올린다(#429). */
    List<MediaObject> findByRefTypeAndRefIdOrderByIdAsc(String refType, String refId);

    /** 여러 글에 붙은 것을 한 번에. 피드가 스무 번 묻지 않게 한다. */
    List<MediaObject> findByRefTypeAndRefIdInOrderByIdAsc(String refType, Collection<String> refIds);

    /**
     * 붙인다 — <b>조건이 판정이다</b>(#86 원칙 5). 내 것이고, 아직 안 붙었고, {@code ready}
     * 인 행만 바뀐다. 돌아오는 수가 요청한 id 수보다 작으면 그중 하나가 남의 것이거나 이미
     * 붙은 것이거나 아직 안 올라온 것이다 — 부르는 쪽이 그때 전부 되돌린다.
     *
     * <p>{@code clearAutomatically} 는 벌크 UPDATE 뒤 영속성 컨텍스트의 옛 사본을 버리기
     * 위해서다. 안 비우면 같은 트랜잭션에서 다시 읽을 때 {@code ref_type} 이 {@code null} 인
     * 옛 값이 나온다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update MediaObject m
               set m.refType = :refType, m.refId = :refId
             where m.id in :ids
               and m.ownerId = :ownerId
               and m.refType is null
               and m.status = :ready
            """)
    int attach(@Param("refType") String refType,
               @Param("refId") String refId,
               @Param("ids") Collection<Long> ids,
               @Param("ownerId") String ownerId,
               @Param("ready") MediaStatus ready);

    /**
     * 안 붙은 채 오래된 것 — 고아 청소가 묻는다. {@code categories} 로 좁히는 이유는 감정 여행
     * 시절의 행(JOURNEY_IMAGE 등)을 건드리지 않기 위해서다. {@code idx_media_orphan} 을 탄다.
     */
    List<MediaObject> findByRefTypeIsNullAndCategoryInAndCreatedAtBefore(
            Collection<UploadCategory> categories, Instant cutoff);
}

package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import jakarta.persistence.*;
import java.time.Instant;

/**
 * 업로드된 파일의 메타데이터 엔티티.
 * - DB에는 S3 object key를 저장(CloudFront URL은 런타임 조립)
 * - 주의: MySQL 예약어 'key' 충돌을 피하기 위해 컬럼명을 'media_key'로 사용. ①
 */
@Entity
@Table(
    name = "media_objects",
    indexes = {
        @Index(name = "idx_media_owner", columnList = "owner_id"),
        @Index(name = "idx_media_ref", columnList = "ref_type, ref_id")
    }
)
public class MediaObject {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** 업로드 카테고리 (문자열로 저장) */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private UploadCategory category;

    /** 업로더/소유자 식별자 */
    @Column(name = "owner_id", nullable = false)
    private String ownerId;

    /** 참조 타입(예: JOURNEY/REVIEW/PROFILE 등) */
    @Column(name = "ref_type")
    private String refType;

    /** 참조 ID(예: journeyId, reviewId 등) */
    @Column(name = "ref_id")
    private String refId;

    /**
     * S3 object key
     * - 컬럼명을 'media_key'로 매핑해 MySQL 예약어 충돌 회피 ①
     * - 유니크 보장(동일 키 중복 업로드 방지)
     */
    @Column(name = "media_key", nullable = false, unique = true, length = 512)
    private String objectKey;

    /** 원본 파일명 */
    @Column(name = "original_name")
    private String originalName;

    /** MIME 타입 */
    @Column(name = "content_type")
    private String contentType;

    /** 바이트 크기 */
    @Column(nullable = false)
    private long size;

    /** 생성 시각 */
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    /** 갱신 시각 */
    @Column(name = "updated_at")
    private Instant updatedAt;

    /** 소프트 삭제(옵션) */
    @Column(name = "deleted_at")
    private Instant deletedAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public MediaObject() {}

    public static MediaObject of(UploadCategory cat,
                                 String ownerId,
                                 String refType,
                                 String refId,
                                 String objectKey,      // ← 파라미터명도 objectKey로
                                 String originalName,
                                 String contentType,
                                 long size) {
        MediaObject m = new MediaObject();
        m.category = cat;
        m.ownerId = ownerId;
        m.refType = refType;
        m.refId = refId;
        m.objectKey = objectKey;       // ← 필드도 objectKey 사용
        m.originalName = originalName;
        m.contentType = contentType;
        m.size = size;
        return m;
    }

    // getters/setters
    public Long getId() { return id; }
    public UploadCategory getCategory() { return category; }
    public void setCategory(UploadCategory c) { this.category = c; }
    public String getOwnerId() { return ownerId; }
    public void setOwnerId(String s) { this.ownerId = s; }
    public String getRefType() { return refType; }
    public void setRefType(String r) { this.refType = r; }
    public String getRefId() { return refId; }
    public void setRefId(String r) { this.refId = r; }

    /** S3 object key 접근자 */
    public String getObjectKey() { return objectKey; }
    public void setObjectKey(String k) { this.objectKey = k; }

    public String getOriginalName() { return originalName; }
    public void setOriginalName(String o) { this.originalName = o; }
    public String getContentType() { return contentType; }
    public void setContentType(String c) { this.contentType = c; }
    public long getSize() { return size; }
    public void setSize(long s) { this.size = s; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getDeletedAt() { return deletedAt; }
    public void setDeletedAt(Instant d) { this.deletedAt = d; }
}

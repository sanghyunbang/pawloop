package com.heattrip.heat_trip_backend.S3.media;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import jakarta.persistence.*;
import org.hibernate.annotations.Check;

import java.time.Instant;

/**
 * 업로드된 파일의 메타데이터 엔티티.
 * - DB에는 S3 object key를 저장(CloudFront URL은 런타임 조립)
 * - 주의: MySQL 예약어 'key' 충돌을 피하기 위해 컬럼명을 'media_key'로 사용. ①
 *
 * <h2>글에 붙는 사진·영상도 이 표다 (#429)</h2>
 * <p>{@code ref_type='POST'}·{@code ref_id=post.id} 로 붙는다. 표를 새로 안 만든 이유는 이
 * 표가 처음부터 "어느 도메인의 무엇에 붙었나" 를 {@code ref_type}·{@code ref_id} 로 들게
 * 만들어졌기 때문이다 — 같은 원장을 둘로 나누면 삭제·청소가 두 벌이 된다.
 *
 * <p>{@code ownerId} 가 {@code String} 인 것은 감정 여행 시절의 흔적이다({@link MediaService}
 * javadoc 의 표). 지금 들어가는 값은 {@code users.id} 를 문자열로 적은 것이고, 소유권 검사는
 * {@code String.equals} 다.
 *
 * <h2>{@code status} 와 {@code poster_key} 는 영상 때문에 있다</h2>
 * <p>영상은 앱이 S3 에 직접 올린다 — 서버를 지나면 Cloudflare 가 100MB 에서 끊는다. 그래서
 * "자리는 잡았는데 아직 안 올라온"({@link MediaStatus#PENDING}) 상태가 생기고, 썸네일도 앱이
 * 만들어 따로 올린다. 사진은 둘 다 안 쓴다 — 받는 순간 {@code READY} 고 포스터가 없다.
 *
 * <h2>{@code width}·{@code height} 는 앱이 준다</h2>
 * <p>서버가 이미지를 열어 재지 않는다 — Mac mini 한 대의 CPU 다. 앱은 어차피 올리기 전에
 * 다시 인코딩하므로 크기를 안다. 피드가 이 값으로 자리를 미리 잡는다.
 */
@Entity
@Table(
    name = "media_objects",
    indexes = {
        @Index(name = "idx_media_owner", columnList = "owner_id"),
        @Index(name = "idx_media_ref", columnList = "ref_type, ref_id"),
        // 고아 청소가 묻는 유일한 질문 — "안 붙은 채 오래된 것". (#429 · #86 원칙 2)
        @Index(name = "idx_media_orphan", columnList = "ref_type, created_at")
    }
)
@Check(name = "ck_media_status", constraints = "status in ('pending','ready')")
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

    /** 참조 타입(예: JOURNEY/REVIEW/PROFILE/POST). {@code null} 이면 아직 어디에도 안 붙었다. */
    @Column(name = "ref_type")
    private String refType;

    /** 참조 ID(예: journeyId, reviewId, postId) */
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

    /** 파일이 S3 에 있는가. 사진은 받는 순간 {@code READY}, 영상은 앱이 다 올렸다고 알려야 {@code READY}. */
    @Convert(converter = MediaStatus.Codec.class)
    @Column(name = "status", nullable = false, length = 10)
    private MediaStatus status;

    /** 영상 썸네일의 S3 키. 사진은 {@code null}. */
    @Column(name = "poster_key", length = 512)
    private String posterKey;

    /** 픽셀 폭. 앱이 준다 — 서버는 이미지를 안 연다. */
    @Column(name = "width")
    private Integer width;

    @Column(name = "height")
    private Integer height;

    /** 영상 길이(ms). 사진은 {@code null}. */
    @Column(name = "duration_ms")
    private Integer durationMs;

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
        // multipart 로 받은 것은 이 순간 S3 에 있다. 영상의 자리 잡기만 PENDING 을 명시한다.
        if (status == null) status = MediaStatus.READY;
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

    /** 글에 붙었는가. {@code ref_type} 이 채워졌으면 붙은 것이다 — 상태 컬럼이 따로 없다. */
    public boolean isAttached() {
        return refType != null;
    }

    /** 이 미디어가 사람 눈으로 그려지는 종류. 카테고리가 정한다. */
    public boolean isVideo() {
        return category != null && category.isVideo();
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
    public MediaStatus getStatus() { return status; }
    public void setStatus(MediaStatus s) { this.status = s; }
    public String getPosterKey() { return posterKey; }
    public void setPosterKey(String k) { this.posterKey = k; }
    public Integer getWidth() { return width; }
    public Integer getHeight() { return height; }
    /** 둘을 함께 받는다 — 한쪽만 있는 크기는 자리를 못 잡는다. */
    public void setDimensions(Integer width, Integer height) {
        this.width = width;
        this.height = height;
    }
    public Integer getDurationMs() { return durationMs; }
    public void setDurationMs(Integer d) { this.durationMs = d; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getDeletedAt() { return deletedAt; }
    public void setDeletedAt(Instant d) { this.deletedAt = d; }
}

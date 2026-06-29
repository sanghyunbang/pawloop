package com.heattrip.heat_trip_backend.S3;

/**
 * 업로드 컨텍스트 DTO.
 * - category: 정책 선택
 * - ownerId : 사용자 식별자(권한/분리)
 * - subPath : 선택적 하위경로(리뷰ID 등)
 */
public record UploadRequest(
    UploadCategory category,
    String ownerId,
    String subPath
) {
    public static UploadRequest of(UploadCategory c, String ownerId) {
        return new UploadRequest(c, ownerId, null);
    }
    public UploadRequest withSubPath(String sub) {
        return new UploadRequest(category, ownerId, sub);
    }
}

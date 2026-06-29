package com.heattrip.heat_trip_backend.S3;

import java.util.Set;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 업로드 범주 정책(경로 prefix, 허용타입, 최대크기).
 */
@Schema(description = "Upload category; controls S3 prefix, allowed MIME types and size limits")
public enum UploadCategory {
    JOURNEY_IMAGE("journeys", Set.of("image/jpeg","image/png","image/webp","image/gif"), 10 * 1024 * 1024L),
    PROFILE_IMAGE("profiles", Set.of("image/jpeg","image/png","image/webp"),              5  * 1024 * 1024L),
    REVIEW_IMAGE ("reviews",  Set.of("image/jpeg","image/png","image/webp"),              10 * 1024 * 1024L);

    public final String prefix;
    public final Set<String> allowed;
    public final long max;

    UploadCategory(String prefix, Set<String> allowed, long max) {
        this.prefix = prefix;
        this.allowed = allowed;
        this.max = max;
    }
}

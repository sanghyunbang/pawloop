package com.heattrip.heat_trip_backend.S3.media.dto;

import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.media.MediaObject;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 계약의 {@code MediaItem} — 업로드 한 건.
 *
 * <p>{@code status} 는 계약의 소문자({@code ready})로 나간다. {@code width}·{@code height} 는
 * 앱이 올릴 때 준 값이라 없을 수 있다(#429).
 */
@Schema(name = "MediaItemResponse", description = "Stored media metadata & access info")
public record MediaItemResponse(
    @Schema(description = "DB primary key") Long id,
    @Schema(description = "S3 object key") String key,
    @Schema(description = "Public (CDN) URL") String url,
    @Schema(description = "MIME type") String contentType,
    @Schema(description = "Size in bytes") Long size,
    @Schema(description = "Upload category") UploadCategory category,
    @Schema(description = "Reference type (e.g., POST)") String refType,
    @Schema(description = "Reference id (e.g., postId)") String refId,
    @Schema(description = "pending | ready") String status,
    @Schema(description = "Video poster (CDN) URL, null for images") String posterUrl,
    @Schema(description = "Pixel width, if the app told us") Integer width,
    @Schema(description = "Pixel height, if the app told us") Integer height,
    @Schema(description = "Video length in ms, null for images") Integer durationMs
) {

    /** URL 은 부르는 쪽이 조립해 준다 — DTO 가 저장소를 모르게 둔다. */
    public static MediaItemResponse of(MediaObject m, String url, String posterUrl) {
        return new MediaItemResponse(
                m.getId(),
                m.getObjectKey(),
                url,
                m.getContentType(),
                m.getSize(),
                m.getCategory(),
                m.getRefType(),
                m.getRefId(),
                m.getStatus() == null ? null : m.getStatus().wire(),
                posterUrl,
                m.getWidth(),
                m.getHeight(),
                m.getDurationMs());
    }
}

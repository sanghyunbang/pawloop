package com.heattrip.heat_trip_backend.S3.media.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import com.heattrip.heat_trip_backend.S3.UploadCategory;

@Schema(name = "MediaItemResponse", description = "Stored media metadata & access info")
public record MediaItemResponse(
    @Schema(description = "DB primary key") Long id,
    @Schema(description = "S3 object key") String key,
    @Schema(description = "Public (CDN) URL") String url,
    @Schema(description = "MIME type") String contentType,
    @Schema(description = "Size in bytes") Long size,
    @Schema(description = "Upload category") UploadCategory category,
    @Schema(description = "Reference type (e.g., JOURNEY/REVIEW/PROFILE)") String refType,
    @Schema(description = "Reference id (e.g., journeyId/reviewId)") String refId
) {}

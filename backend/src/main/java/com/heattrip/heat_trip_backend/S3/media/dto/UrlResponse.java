package com.heattrip.heat_trip_backend.S3.media.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(name = "UrlResponse")
public record UrlResponse(
    @Schema(description = "Accessible URL") String url
) {}

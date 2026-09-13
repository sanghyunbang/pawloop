package com.heattrip.heat_trip_backend.S3.media.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 계약의 {@code VideoUploadTicket} — 자리 잡기의 답 (#429).
 *
 * <p>{@code uploadUrl} 로 앱이 S3 에 PUT 한 뒤 {@code POST /media/{id}/complete} 를 부른다.
 * {@code key} 는 앱이 쓸 일이 없다 — 어디에 올라갔는지 사람이 볼 때를 위해 싣는다.
 */
@Schema(name = "VideoUploadTicket", description = "Where to PUT the video, and the row that waits for it")
public record VideoTicketResponse(
        @Schema(description = "media id — send it to complete, then in mediaIds") Long id,
        @Schema(description = "S3 object key the file will live at") String key,
        @Schema(description = "Presigned PUT URL. Same Content-Type as reserved, 15 minutes") String uploadUrl) {
}

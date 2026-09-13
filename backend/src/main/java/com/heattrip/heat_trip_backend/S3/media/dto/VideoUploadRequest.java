package com.heattrip.heat_trip_backend.S3.media.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 계약의 {@code VideoUploadRequest} — 영상 자리 잡기 (#429).
 *
 * <p>파일은 여기 없다. 앱이 올릴 파일의 <b>형식·크기·길이·픽셀</b>만 알린다. 서버는 그 크기로
 * 자리를 잡고 서명 PUT 을 돌려주며, 올라온 뒤 {@code complete} 에서 실제 크기가 이 값과 같은지
 * 잰다 — 서명 PUT 은 크기 조건을 못 걸기 때문이다.
 *
 * <p>상한(60초 · 150MB · mp4/mov)은 여기 애너테이션이 아니라 {@code MediaService} 가 잰다 —
 * 숫자가 카테고리 정책({@code UploadCategory.POST_VIDEO})과 한 곳에 살게 두려고.
 */
@Schema(name = "VideoUploadRequest", description = "Reserve a slot for a video the app will PUT to S3 directly")
public record VideoUploadRequest(
        @Schema(description = "video/mp4 or video/quicktime", example = "video/mp4")
        @NotBlank String contentType,

        @Schema(description = "Exact byte size of the file the app will upload")
        @NotNull @Positive Long size,

        @Schema(description = "Pixel width after the app re-encoded it — with height, or neither")
        @Positive Integer width,

        @Positive Integer height,

        @Schema(description = "Length in milliseconds. 60 s at most")
        @NotNull @Positive Integer durationMs) {
}
